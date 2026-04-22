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

uid=$(id -u)
cache="/tmp/tmux-cursor-spend-${uid}"
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

day_result=$(awk "BEGIN{printf \"\$%.2f\", $day_cents / 100}")
month_result=$(awk "BEGIN{printf \"\$%.2f\", $month_cents / 100}")
result="󰆦 ${day_result} | ${month_result}"

printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
