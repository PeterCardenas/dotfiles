#!/usr/bin/env bash
# Daily Cursor spend (UTC) for tmux status bar.
# Calls the Cursor DashboardService ConnectRPC API with today's UTC start.
# Caches result for 120s to avoid hammering the API.
export LC_ALL=C

log_error() {
  printf 'cursor_spend: %s\n' "$1" >&2
}

fetch_total_cents() {
  local start_ms="$1"
  local resp
  local cents

  resp=$(curl -sS --max-time 5 -X POST "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "{\"startDate\":\"$start_ms\"}") || {
    log_error "failed to fetch usage events"
    printf '0'
    return 0
  }

  cents=$(printf '%s' "$resp" | jq -r '.totalCostCents // 0') || {
    log_error "failed to parse totalCostCents from API response"
    printf '0'
    return 0
  }

  if [ -z "$cents" ]; then
    printf '0'
  else
    printf '%s' "$cents"
  fi
}

remaining_color() {
  local remaining_cents="$1"
  local daily_cents="$2"

  # Treat today's spend as one day of runway.
  awk -v remaining="$remaining_cents" -v daily="$daily_cents" 'BEGIN {
    if (remaining == "") print "#c0caf5"
    else if (remaining <= daily) print "#f7768e"
    else if (remaining <= daily * 3) print "#ff9e64"
    else if (remaining < daily * 7) print "#e0af68"
    else print "#9ece6a"
  }'
}

short=false
[ "$1" = "--short" ] && short=true

uid=$(id -u)
cache="/tmp/tmux-cursor-spend-${uid}"
$short && cache="${cache}-short"
now=$(date +%s)
if [ -f "$cache" ]; then
  age=$((now - $(head -1 "$cache")))
  if [ "$age" -lt 120 ]; then
    sed -n '2p' "$cache"
    exit 0
  fi
fi

# Get access token (macOS keychain or Linux file)
if [ "$(uname)" = "Darwin" ]; then
  token=$(security find-generic-password -s "cursor-access-token" -a "cursor-user" -w 2>/dev/null)
else
  auth_file="${XDG_CONFIG_HOME:-$HOME/.config}/cursor/auth.json"
  if [ -f "$auth_file" ]; then
    token=$(jq -r '.accessToken' "$auth_file" 2>/dev/null)
  fi
fi

if [ -z "$token" ]; then
  printf '%s\n' "$now" >"$cache"
  exit 0
fi

# UTC midnight today in epoch millis
day_start_ms=$(date -u -d "today 00:00:00" +%s000 2>/dev/null || date -u -j -f "%H:%M:%S" "00:00:00" +%s000 2>/dev/null)
month_ymd=$(date -u +%Y-%m-01)
month_start_ms=$(date -u -d "${month_ymd} 00:00:00" +%s000 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "${month_ymd} 00:00:00" +%s000 2>/dev/null)

day_cents=$(fetch_total_cents "$day_start_ms")
month_cents=$(fetch_total_cents "$month_start_ms")

# The dashboard REST API expects the JWT subject alongside the access token.
payload=${token#*.}
payload=${payload%%.*}
case $((${#payload} % 4)) in
2) payload="${payload}==" ;;
3) payload="${payload}=" ;;
esac
decoded_payload=$(printf '%s' "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null ||
  printf '%s' "$payload" | tr '_-' '/+' | base64 -D 2>/dev/null)
user_id=$(printf '%s' "$decoded_payload" | jq -r '.sub // empty' 2>/dev/null)

remaining_cents=
if [ -n "$user_id" ]; then
  usage_summary=$(curl -sS --max-time 5 "https://cursor.com/api/usage-summary" \
    -H "Cookie: WorkosCursorSessionToken=${user_id}%3A%3A${token}" 2>/dev/null)
  remaining_cents=$(printf '%s' "$usage_summary" |
    jq -r '.individualUsage.onDemand.remaining // .individualUsage.overall.remaining // .teamUsage.onDemand.remaining // empty' 2>/dev/null)
fi

day_result=$(awk "BEGIN{printf \"\$%.2f\", $day_cents / 100}")
month_result=$(awk "BEGIN{printf \"\$%.2f\", $month_cents / 100}")
color=$(remaining_color "$remaining_cents" "$day_cents")
if $short; then
  result="󰆦 #[fg=${color}]${month_result}"
else
  result="󰆦 ${day_result} | #[fg=${color}]${month_result}"
fi

printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
