#!/usr/bin/env bash
# Claude usage-credit spend for the tmux status bar.
#
# Reads the figure Claude itself reports (GET /api/oauth/usage) with the Claude
# Code OAuth token. That number is authoritative, account-wide (every machine
# already included) and billing-cycle scoped, so nothing here derives cost from
# transcripts or aggregates per-session accounting.
#
# The endpoint exposes no per-day breakdown (extra_usage.daily and .weekly are
# null and no query parameter populates them; daily buckets exist only on the
# admin-keyed Analytics API). Today's spend is therefore derived by
# checkpointing the authoritative cumulative counter once a day and differencing
# it.
#
# A failed fetch keeps showing the last good figure: a blip, a rate limit or an
# expired token must not read as "$0 spent", nor leave a hole where the segment
# was.
export LC_ALL=C

short=false
[ "$1" = "--short" ] && short=true

# shellcheck source=spend_format.sh
. "$(cd "$(dirname "$0")" && pwd)/spend_format.sh"

# Every running Claude Code and ACP session polls this same endpoint on the same
# token, and it answers a burst with a 429 that outlasts several minutes. A
# status bar has no business competing for that budget, and cycle-to-date spend
# does not move fast enough to need a tighter refresh.
usage_ttl=300
# Cycle-to-date spend moves slowly, so an old reading is still worth showing —
# far better than a hole in the status bar, and a sustained rate limit outlasts
# any short staleness bound. It is dropped only once it is old enough to be
# meaningless, which is also the only guard against a days-old figure passing
# for a current one.
usage_max_stale=21600
# Anthropic documents ~1 request/minute as the sustained ceiling and answers
# bursts with a 429 carrying Retry-After (17 minutes, once observed). That
# header is authoritative; this is only the fallback when it is missing.
usage_rate_limit_backoff=600
usage_max_backoff=3600

# Day boundaries are local, not UTC: UTC midnight lands at 17:00 PT, mid
# workday, which would split a single working day across two "days".
today=$(date +%Y-%m-%d)
history_file="${XDG_DATA_HOME:-$HOME/.local/share}/claude-spend/history"

# Prints "<status> <retry_after_seconds>" on line 1 and, on success,
# "<used> <exponent> <limit> <percent> <severity>" on line 2 — monetary fields
# in minor units, "-" for a field the API omits. Line 2 is empty on any failure.
# Both come back through stdout because the caller runs this in a command
# substitution, where a global assignment would not survive the subshell.
#
# The `spend` block is preferred over `extra_usage`: it carries the currency
# exponent and Claude's own severity rating. `extra_usage` is the fallback,
# being the shape the CLI itself parses.
fetch_usage() {
  local creds token body headers status retry_after
  creds="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
  [ -f "$creds" ] || return 0
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
  [ -n "$token" ] || return 0

  body=$(mktemp) || return 0
  headers=$(mktemp) || { rm -f "$body"; return 0; }
  status=$(curl -sS --max-time 5 -o "$body" -D "$headers" -w '%{http_code}' \
    "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" 2>/dev/null)
  # A rate-limited response says how long it wants to be left alone; obeying it
  # beats guessing, especially since every Claude Code session on this machine
  # shares the token's budget.
  retry_after=$(awk 'tolower($1) == "retry-after:" { gsub(/[^0-9]/, "", $2); print $2; exit }' \
    "$headers")
  rm -f "$headers"
  printf '%s %s\n' "${status:-000}" "${retry_after:-0}"

  if [ "$status" != "200" ]; then
    rm -f "$body"
    return 0
  fi

  # Both blocks are absent (or disabled) when usage credits are not active for
  # the account, in which case there is no spend to report.
  jq -r '
    (.spend // {}) as $spend
    | (.extra_usage // {}) as $extra
    | select($spend.enabled == true or $extra.is_enabled == true)
    | [($spend.used.amount_minor // $extra.used_credits // "-"),
       ($spend.used.exponent // $extra.decimal_places // 2),
       ($spend.limit.amount_minor // $extra.monthly_limit // "-"),
       ($spend.percent // $extra.utilization // "-"),
       ($spend.severity // "-")]
    | select(.[0] != "-")
    | @tsv' "$body" 2>/dev/null
  rm -f "$body"
}

# Claude's own rating of the current spend level, so the segment agrees with
# what /usage and the member dashboard show. Only "warning" (at 81%) has been
# observed in the wild, so an unrecognized value falls through to the percentage
# tiers rather than silently losing the color.
severity_color() {
  case "$1" in
  critical | exceeded | error | danger) printf '#f7768e' ;;
  warning) printf '#ff9e64' ;;
  info | caution) printf '#e0af68' ;;
  ok | none | normal) printf '#9ece6a' ;;
  *) return 1 ;;
  esac
}

percent_color() {
  awk -v pct="$1" 'BEGIN {
    if (pct == "-" || pct == "") print "#c0caf5"
    else if (pct >= 90) print "#f7768e"
    else if (pct >= 75) print "#ff9e64"
    else if (pct >= 50) print "#e0af68"
    else print "#9ece6a"
  }'
}

# Minor units (cents for USD) to a plain dollar amount.
major_units() {
  awk -v minor="$1" -v places="$2" 'BEGIN { printf "%.2f", minor / (10 ^ places) }'
}

# Closing reading of the most recent day before today, in minor units.
previous_day_reading() {
  [ -f "$history_file" ] || return 0
  awk -v today="$today" '$1 < today { reading = $2 } END { if (reading != "") print reading }' \
    "$history_file"
}

# Checkpoint the cumulative counter for today, replacing any earlier reading for
# the same day, and drop days past the retention cutoff. Called only after a
# successful fetch, so a stale cached figure never becomes a checkpoint. Two
# concurrent runs can lose one update to each other; the next fetch re-records
# the same value, so racing costs nothing and no lock is warranted.
record_reading() {
  local used=$1 cutoff tmp
  cutoff=$(date -d '31 days ago' +%Y-%m-%d 2>/dev/null || date -v-31d +%Y-%m-%d) || return 0
  mkdir -p "$(dirname "$history_file")" || return 0
  tmp=$(mktemp "${history_file}.XXXXXX") || return 0
  {
    [ -f "$history_file" ] &&
      awk -v today="$today" -v cutoff="$cutoff" '$1 != today && $1 >= cutoff' "$history_file"
    printf '%s %s\n' "$today" "$used"
  } | sort -u >"$tmp" && mv -f "$tmp" "$history_file" || rm -f "$tmp"
}

now=$(date +%s)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-spend"
cache="${cache_dir}/usage"
mkdir -p "$cache_dir"

# Cache layout: line 1 = earliest next attempt, line 2 = last good reading,
# line 3 = epoch of that reading. Line 1 paces requests even when they fail;
# line 3 is what bounds how long a stale reading stays on screen.
next_attempt=0
usage=
last_ok=0
if [ -f "$cache" ]; then
  next_attempt=$(head -1 "$cache")
  case "$next_attempt" in '' | *[!0-9]*) next_attempt=0 ;; esac
  usage=$(sed -n '2p' "$cache")
  last_ok=$(sed -n '3p' "$cache")
  case "$last_ok" in '' | *[!0-9]*) last_ok=0 ;; esac
fi

if [ "$now" -ge "$next_attempt" ]; then
  attempt=$(fetch_usage)
  read -r status retry_after <<<"$(head -1 <<<"$attempt")"
  fresh=$(sed -n '2p' <<<"$attempt")
  if [ -n "$fresh" ]; then
    usage=$fresh
    last_ok=$now
    record_reading "$(awk '{ print $1 }' <<<"$fresh")"
  fi
  if [ "$status" = "429" ]; then
    backoff=$usage_rate_limit_backoff
    case "$retry_after" in
    '' | 0 | *[!0-9]*) ;;
    *) backoff=$retry_after ;;
    esac
    # A server can always name an absurd delay; cap it so the segment recovers.
    [ "$backoff" -gt "$usage_max_backoff" ] && backoff=$usage_max_backoff
    next_attempt=$((now + backoff))
  else
    next_attempt=$((now + usage_ttl))
  fi
  printf '%s\n%s\n%s' "$next_attempt" "$usage" "$last_ok" >"$cache"
fi

[ -n "$usage" ] || exit 0
[ "$((now - last_ok))" -lt "$usage_max_stale" ] || exit 0

read -r used_minor exponent limit_minor percent severity <<<"$usage"

# The API sends percent alongside the limit, but derive it when absent so a
# known limit always colors the segment.
if [ "$percent" = "-" ] && [ "$limit_minor" != "-" ]; then
  percent=$(awk -v used="$used_minor" -v limit="$limit_minor" \
    'BEGIN { print (limit > 0) ? used / limit * 100 : "-" }')
fi

color=$(severity_color "$severity") || color=$(percent_color "$percent")
used_display=$(major_units "$used_minor" "$exponent")

if $short; then
  printf '%s' "#[fg=#ff9e64]  #[fg=${color}]$(format_short_money "$used_display")"
  exit 0
fi

segment="#[fg=${color}]\$${used_display}"

# Today is the counter's rise since yesterday's closing checkpoint, so it only
# appears once a previous day has been recorded. A drop means the billing cycle
# rolled over, which makes the whole counter today's spend.
previous_reading=$(previous_day_reading)
if [ -n "$previous_reading" ]; then
  today_minor=$(awk -v now="$used_minor" -v prev="$previous_reading" \
    'BEGIN { print (now >= prev) ? now - prev : now }')
  segment="\$$(major_units "$today_minor" "$exponent") #[fg=#565f89]| ${segment}"
fi

# A null limit means unlimited: there is no ratio to show.
if [ "$limit_minor" != "-" ]; then
  segment="${segment} #[fg=#565f89]/ #[fg=#c0caf5]\$$(major_units "$limit_minor" "$exponent")"
fi

printf '%s' "#[fg=#ff9e64]  #[fg=#c0caf5]${segment}"
