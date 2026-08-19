#!/usr/bin/env bash
# Tests for executable_claude_spend.sh.
#
# The segment is driven by the /api/oauth/usage response plus a per-day
# checkpoint of the cumulative counter. The cases that matter are: how a reading
# is formatted and colored, how today's figure is differenced out of the
# checkpoints, and how the cache behaves when the fetch fails (a blip must never
# render as "$0 spent", and must never poison the checkpoints).
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
script="$script_dir/executable_claude_spend.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export XDG_CACHE_HOME="$tmp/cache"
export XDG_DATA_HOME="$tmp/data"
export CLAUDE_CONFIG_DIR="$tmp/claude"
cache="$tmp/cache/claude-spend/usage"
history="$tmp/data/claude-spend/history"

failures=0
check() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$label" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

# Emulates `curl -o <file> -w '%{http_code}'`: writes the staged body to the -o
# path and prints the status. Exits nonzero like curl does on a transport error
# when FAKE_CURL_FAIL is set. FAKE_SIBLING_CACHE stands in for another copy of
# the script updating the cache while this request is in flight.
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=
headers=
prev=
for arg in "$@"; do
  [ "$prev" = "-o" ] && out=$arg
  [ "$prev" = "-D" ] && headers=$arg
  prev=$arg
done
if [ -n "${FAKE_CURL_COUNT:-}" ]; then
  printf 'request\n' >>"$FAKE_CURL_COUNT"
  sleep 0.2
fi
if [ -n "${FAKE_SIBLING_CACHE:-}" ]; then
  printf '%s' "$FAKE_SIBLING_LINES" >"$FAKE_SIBLING_CACHE"
fi
[ -n "${FAKE_CURL_FAIL:-}" ] && exit 7
[ -n "$out" ] && cat "$FAKE_USAGE_JSON" >"$out"
if [ -n "$headers" ]; then
  printf 'HTTP/2 %s\r\n' "${FAKE_HTTP_STATUS:-200}" >"$headers"
  [ -n "${FAKE_RETRY_AFTER:-}" ] && printf 'retry-after: %s\r\n' "$FAKE_RETRY_AFTER" >>"$headers"
fi
printf '%s' "${FAKE_HTTP_STATUS:-200}"
EOF
chmod +x "$tmp/bin/curl"

write_credentials() {
  mkdir -p "$CLAUDE_CONFIG_DIR"
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat-test"}}' \
    >"$CLAUDE_CONFIG_DIR/.credentials.json"
}

# A full response: the `spend` block the script prefers alongside the
# `extra_usage` block it falls back to. `-` means the test wants a JSON null.
stage_usage() {
  local used=$1 limit=$2 percent=$3 severity=$4
  local spend_limit=$limit
  [ "$limit" = "-" ] && limit=null && spend_limit=null
  [ "$percent" = "-" ] && percent=null
  cat >"$tmp/usage.json" <<EOF
{"five_hour":null,"limits":[],
 "extra_usage":{"is_enabled":true,"monthly_limit":$limit,"used_credits":$used,
   "utilization":$percent,"currency":"USD","decimal_places":2,"daily":null,"weekly":null},
 "spend":{"used":{"amount_minor":$used,"currency":"USD","exponent":2},
   "limit":{"amount_minor":$spend_limit,"currency":"USD","exponent":2},
   "percent":$percent,"severity":"$severity","enabled":true}}
EOF
  export FAKE_USAGE_JSON="$tmp/usage.json"
  unset FAKE_CURL_FAIL FAKE_HTTP_STATUS FAKE_RETRY_AFTER
}

# An account whose response carries no `spend` block at all.
stage_extra_usage_only() {
  local used=$1 limit=$2 percent=$3
  cat >"$tmp/usage.json" <<EOF
{"extra_usage":{"is_enabled":true,"monthly_limit":$limit,"used_credits":$used,
  "utilization":$percent,"currency":"USD","decimal_places":2}}
EOF
  export FAKE_USAGE_JSON="$tmp/usage.json"
  unset FAKE_CURL_FAIL FAKE_HTTP_STATUS
}

stage_no_extra_usage() {
  printf '{"five_hour":null,"extra_usage":null}' >"$tmp/usage.json"
  export FAKE_USAGE_JSON="$tmp/usage.json"
  unset FAKE_CURL_FAIL FAKE_HTTP_STATUS
}

reset_state() {
  rm -rf "$tmp/cache" "$tmp/data" "$tmp/claude"
  write_credentials
}

# Cache layout: earliest next attempt, last good reading, epoch of that reading.
write_cache() {
  mkdir -p "$(dirname "$cache")"
  printf '%s\n%s\n%s' "$1" "$2" "$3" >"$cache"
}

write_history() {
  mkdir -p "$(dirname "$history")"
  printf '%s\n' "$@" >"$history"
}

now=$(date +%s)
today=$(date +%Y-%m-%d)
yesterday=$(date -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

# --- 1. A normal reading renders the used amount, colored by severity ---
reset_state
stage_usage 121074 150000 81 warning
out=$("$script")
check "used amount rendered in dollars" "yes" \
  "$(grep -q '\$1210.74$' <<<"$out" && echo yes || echo no)"
check "the limit is not rendered" "no" \
  "$(grep -q '\$1500.00' <<<"$out" && echo yes || echo no)"
check "severity warning colors the amount orange" "yes" \
  "$(grep -q 'fg=#ff9e64\]\$1210.74' <<<"$out" && echo yes || echo no)"

# --- 2. --short shows the used amount alone, still colored ---
reset_state
stage_usage 121074 150000 81 warning
check "short form is the compact used amount" "yes" \
  "$(grep -q 'fg=#ff9e64\]\$1.2k$' <<<"$("$script" --short)" && echo yes || echo no)"

# --- 3. Severity drives the color, and outranks the percentage ---
for tier in "ok:#9ece6a:green" "info:#e0af68:yellow" "warning:#ff9e64:orange" "critical:#f7768e:red"; do
  IFS=: read -r severity expected_color name <<<"$tier"
  reset_state
  # 1% used: only severity can be producing a non-green color here.
  stage_usage 1500 150000 1 "$severity"
  check "severity $severity is $name" "yes" \
    "$(grep -q "fg=${expected_color}\]\\\$" <<<"$("$script")" && echo yes || echo no)"
done

# --- 4. An unrecognized severity falls back to the percentage tiers ---
reset_state
stage_usage 135000 150000 90 brand_new_value
check "unknown severity falls back to percent tiers" "yes" \
  "$(grep -q 'fg=#f7768e\]\$1350.00' <<<"$("$script")" && echo yes || echo no)"

# --- 5. A response with no spend block still works off extra_usage ---
reset_state
stage_extra_usage_only 60000 150000 40
out=$("$script")
check "extra_usage fallback: amount rendered" "yes" \
  "$(grep -q '\$600.00$' <<<"$out" && echo yes || echo no)"
check "extra_usage fallback: colored by percent" "yes" \
  "$(grep -q 'fg=#9ece6a\]\$600.00' <<<"$out" && echo yes || echo no)"

# --- 6. A null limit leaves no percent to derive, so no color tier applies ---
reset_state
stage_usage 121074 - - unknown_severity
check "unlimited: uncolored used amount" "yes" \
  "$(grep -q 'fg=#c0caf5\]\$1210.74$' <<<"$("$script")" && echo yes || echo no)"

# --- 7. Percent is derived when the API omits it ---
reset_state
stage_usage 135000 150000 - unknown_severity
check "derived 90% is red" "yes" \
  "$(grep -q 'fg=#f7768e\]\$1350.00' <<<"$("$script")" && echo yes || echo no)"

# --- 8. No usage credits on the account: nothing to show ---
reset_state
stage_no_extra_usage
check "extra_usage null: empty segment" "" "$("$script")"

# --- 9. No credentials to read: empty ---
reset_state
rm -f "$CLAUDE_CONFIG_DIR/.credentials.json"
stage_usage 121074 150000 81 warning
check "missing credentials: empty segment" "" "$("$script")"

# --- 10. Exact yesterday uses its latest reading ---
reset_state
write_history "$yesterday 90000" "$yesterday 100000" "$today 110000"
stage_usage 121074 150000 81 warning
out=$("$script")
check "latest yesterday checkpoint" "#[fg=#ff9e64]  #[fg=#c0caf5]\$210.74 #[fg=#565f89]| #[fg=#ff9e64]\$1210.74" "$out"

# --- 11. Missing yesterday uses earliest today and marks it uncertain ---
reset_state
write_history "$today 110000" "$today 115000"
stage_usage 121074 150000 81 warning
check "earliest today fallback" "#[fg=#ff9e64]  #[fg=#c0caf5]\$110.74? #[fg=#565f89]| #[fg=#ff9e64]\$1210.74" "$("$script")"

# --- 12. Neither baseline produces only unknown today field ---
reset_state
write_history "$(date -d '3 days ago' +%Y-%m-%d) 200000"
stage_usage 121074 150000 81 warning
out=$("$script")
check "missing daily baseline" "#[fg=#ff9e64]  #[fg=#c0caf5]\$? #[fg=#565f89]| #[fg=#ff9e64]\$1210.74" "$out"

# --- 13. Counter reset uses whole current counter ---
reset_state
write_history "$yesterday 200000"
stage_usage 121074 150000 81 warning
check "cycle reset" "yes" "$(grep -q '\$1210.74 #\[fg=#565f89\]| ' <<<"$("$script")" && echo yes || echo no)"

# --- 14. Successful readings retain every checkpoint entry ---
reset_state
write_history "$yesterday 100000" "$today 110000"
stage_usage 121074 150000 81 warning
check "retained ordering and segment" "#[fg=#ff9e64]  #[fg=#c0caf5]\$210.74 #[fg=#565f89]| #[fg=#ff9e64]\$1210.74" "$("$script")"
check "history retains individual readings" "$yesterday 100000
$today 110000
$today 121074" "$(cat "$history")"

# --- 14. A failed fetch must not poison the checkpoints ---
reset_state
write_history "$yesterday 100000"
export FAKE_CURL_FAIL=1
"$script" >/dev/null
check "failed fetch records no checkpoint" "$yesterday 100000" "$(cat "$history")"

# --- 15. Within the TTL the cached reading is served without fetching ---
reset_state
write_cache "$((now + 110))" "121074 2 150000 81 warning" "$((now - 10))"
export FAKE_CURL_FAIL=1
check "fresh cache: served without a fetch" "yes" \
  "$(grep -q 'fg=#ff9e64\]\$1210.74' <<<"$("$script")" && echo yes || echo no)"

# --- 16. A failed fetch keeps the last good reading instead of reporting $0 ---
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 300))"
export FAKE_CURL_FAIL=1
check "fetch fails, reading recent: last good total retained" "yes" \
  "$(grep -q '\$1210.74' <<<"$("$script")" && echo yes || echo no)"
check "fetch fails: last-good epoch is not advanced" "$((now - 300))" \
  "$(sed -n '3p' "$cache")"

# --- 17. An old reading is shown unchanged, not dropped and not marked ---
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 10000))"
export FAKE_CURL_FAIL=1
out=$("$script")
check "old reading: still shown" "yes" \
  "$(grep -q '\$1210.74' <<<"$out" && echo yes || echo no)"
check "old reading: keeps its severity color" "yes" \
  "$(grep -q 'fg=#ff9e64\]\$1210.74' <<<"$out" && echo yes || echo no)"
check "old reading: short form unchanged too" "yes" \
  "$(grep -q 'fg=#ff9e64\]\$1.2k$' <<<"$("$script" --short)" && echo yes || echo no)"

# Beyond the hard cutoff it is too old to mean anything and is dropped.
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 30000))"
export FAKE_CURL_FAIL=1
check "reading beyond the hard cutoff: empty segment" "" "$("$script")"

# --- 18. A failure with nothing cached is empty, not a bogus zero ---
reset_state
export FAKE_CURL_FAIL=1
check "fetch fails with no cache: empty segment" "" "$("$script")"

# --- 19. A 429 backs off far past the normal TTL instead of hammering ---
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 10))"
stage_usage 121074 150000 81 warning
export FAKE_HTTP_STATUS=429
check "rate limited: last good reading still shown" "yes" \
  "$(grep -q '\$1210.74' <<<"$("$script")" && echo yes || echo no)"
check "rate limited: next attempt pushed well past the normal TTL" "yes" \
  "$(awk -v next_at="$(head -1 "$cache")" -v now="$now" \
    'BEGIN { print (next_at - now > 450) ? "yes" : "no" }')"
unset FAKE_HTTP_STATUS

# Retry-After is authoritative when the server sends one.
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 10))"
stage_usage 121074 150000 81 warning
export FAKE_HTTP_STATUS=429 FAKE_RETRY_AFTER=1042
"$script" >/dev/null
check "rate limited: Retry-After is honored over the fallback" "yes" \
  "$(awk -v next_at="$(head -1 "$cache")" -v now="$now" \
    'BEGIN { d = next_at - now; print (d > 900 && d <= 1100) ? "yes" : "no" }')"
unset FAKE_HTTP_STATUS FAKE_RETRY_AFTER

# An absurd Retry-After is capped so the segment still recovers.
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 10))"
stage_usage 121074 150000 81 warning
export FAKE_HTTP_STATUS=429 FAKE_RETRY_AFTER=99999
"$script" >/dev/null
check "rate limited: absurd Retry-After capped at an hour" "yes" \
  "$(awk -v next_at="$(head -1 "$cache")" -v now="$now" \
    'BEGIN { d = next_at - now; print (d > 3000 && d <= 3660) ? "yes" : "no" }')"
unset FAKE_HTTP_STATUS FAKE_RETRY_AFTER

# A non-200 that is not a rate limit keeps the normal cadence.
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 10))"
stage_usage 121074 150000 81 warning
export FAKE_HTTP_STATUS=500
"$script" >/dev/null
# Bounded loosely: the script's own clock runs a beat behind the test's $now,
# and the point is only that this is the normal cadence, not the 600s backoff.
check "server error: normal TTL cadence retained" "yes" \
  "$(awk -v next_at="$(head -1 "$cache")" -v now="$now" \
    'BEGIN { print (next_at - now <= 450) ? "yes" : "no" }')"
unset FAKE_HTTP_STATUS

# --- 20. Concurrent runs must not lose each other's reading ---
# One copy of the script runs per tmux client per redraw, so a fetch is often in
# flight while a sibling records a newer reading. A failure that wrote back its
# own pre-fetch copy of the cache would roll that reading back, and a torn read
# of a half-written cache would blank the segment outright.
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 300))"
export FAKE_CURL_FAIL=1 FAKE_SIBLING_CACHE="$cache"
FAKE_SIBLING_LINES="$((now + 200))
135000 2 150000 90 critical
$now"
export FAKE_SIBLING_LINES
out=$("$script")
check "failed fetch keeps a concurrent run's newer reading" "yes" \
  "$(grep -q '\$1350.00' <<<"$out" && echo yes || echo no)"
check "failed fetch does not roll back the newer epoch" "$now" "$(sed -n '3p' "$cache")"
check "failed fetch still records its own backoff" "yes" \
  "$(awk -v next_at="$(head -1 "$cache")" -v now="$now" \
    'BEGIN { d = next_at - now; print (d > 0 && d <= 450) ? "yes" : "no" }')"
unset FAKE_CURL_FAIL FAKE_SIBLING_CACHE FAKE_SIBLING_LINES

# --- 21. Concurrent stale-cache runs share one API request ---
reset_state
write_cache "$((now - 1))" "121074 2 150000 81 warning" "$((now - 300))"
stage_usage 121074 150000 81 warning
export FAKE_CURL_COUNT="$tmp/curl-count"
: >"$FAKE_CURL_COUNT"
("$script" >/dev/null) & first=$!
("$script" >/dev/null) & second=$!
wait "$first" "$second"
check "concurrent stale cache: one API request" "1" "$(wc -l <"$FAKE_CURL_COUNT")"
unset FAKE_CURL_COUNT

# The cache is swapped in whole, so no partial file is ever left where a reader
# would find it.
reset_state
stage_usage 121074 150000 81 warning
"$script" >/dev/null
check "cache replaced atomically: no temp files left behind" "" \
  "$(find "$(dirname "$cache")" -name 'usage.*' ! -name 'usage.lock' -print)"
check "cache still holds a complete reading" $'121074\t2\t150000\t81\twarning' \
  "$(sed -n '2p' "$cache")"

if [ "$failures" -gt 0 ]; then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
