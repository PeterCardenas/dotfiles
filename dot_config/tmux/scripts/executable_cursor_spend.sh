#!/usr/bin/env bash
# Daily Cursor spend (UTC) for tmux status bar.
# Calls the Cursor DashboardService ConnectRPC API with today's UTC start.
# Caches result for 120s to avoid hammering the API.
export LC_ALL=C

log_error() {
  printf 'cursor_spend: %s\n' "$1" >&2
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
start_ms=$(date -u -d "today 00:00:00" +%s000 2>/dev/null || date -u -j -f "%H:%M:%S" "00:00:00" +%s000 2>/dev/null)

resp=$(curl -sS --max-time 5 -X POST "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d "{\"startDate\":\"$start_ms\"}") || {
  log_error "failed to fetch usage events"
  resp=""
}

cents=$(printf '%s' "$resp" | jq -r '.totalCostCents // 0') || {
  log_error "failed to parse totalCostCents from API response"
  cents="0"
}

if [ -z "$cents" ] || [ "$cents" = "0" ]; then
  result=""
else
  result=$(awk "BEGIN{printf \"󰬁 \$%.2f\", $cents / 100}")
fi

printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
