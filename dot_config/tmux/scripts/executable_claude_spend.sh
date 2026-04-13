#!/usr/bin/env bash
# Daily Claude spend (UTC) from nvim agentic sessions for tmux status bar.
# PID files contain lines of "YYYY-MM-DD <cost>".
# Sums today's (UTC) values from: daily aggregate + live PID files.
# Dead PID files are rolled into the daily aggregate before pruning.
# When not --local, also aggregates spend from a peer machine via SSH.
# Caches: local result 10s, remote result 30s.
export LC_ALL=C

local_only=false
if [ "$1" = "--local" ]; then
  local_only=true
fi

uid=$(id -u)
now=$(date +%s)

# Check main cache (only when producing formatted output)
if [ "$local_only" = false ]; then
  cache="/tmp/tmux-claude-spend-${uid}"
  if [ -f "$cache" ]; then
    age=$((now - $(head -1 "$cache")))
    if [ "$age" -lt 10 ]; then
      sed -n '2p' "$cache"
      exit 0
    fi
  fi
fi

spend_dir="/tmp/claude-spend-nvim-${uid}"
today=$(date -u +%Y-%m-%d)
daily_file="${spend_dir}/daily-${today}"

# Read current daily aggregate
daily_total=0
if [ -f "$daily_file" ]; then
  daily_total=$(cat "$daily_file" 2>/dev/null)
  daily_total=${daily_total:-0}
fi

# Extract today's cost from a PID file (lines: "YYYY-MM-DD <cost>")
pid_today() {
  awk -v d="$today" '$1 == d { sum += $2 } END { printf "%.4f", sum }' "$1" 2>/dev/null
}

# Sum live PID files; roll dead ones into daily aggregate
live_total=0
stale_total=0
if [ -d "$spend_dir" ]; then
  for f in "$spend_dir"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in daily-*) continue ;; esac
    val=$(pid_today "$f")
    val=${val:-0}
    if kill -0 "$base" 2>/dev/null; then
      live_total=$(awk "BEGIN{printf \"%.4f\", $live_total + $val}")
    else
      stale_total=$(awk "BEGIN{printf \"%.4f\", $stale_total + $val}")
      rm -f "$f"
    fi
  done
fi

# Persist stale spend into daily file
if [ "$stale_total" != "0" ] && [ "$stale_total" != "0.0000" ]; then
  daily_total=$(awk "BEGIN{printf \"%.4f\", $daily_total + $stale_total}")
  printf '%s' "$daily_total" >"$daily_file"
fi

local_total=$(awk "BEGIN{printf \"%.4f\", $daily_total + $live_total}")

# --local: output raw number for remote aggregation, skip formatting/remote
if [ "$local_only" = true ]; then
  printf '%s' "$local_total"
  exit 0
fi

# --- Remote aggregation ---
# Determine peer SSH host based on local hostname.
# macbook → desktop, desktop → macbook (both via tailscale)
remote_host=""
case "$(hostname)" in
*MacBook* | *macbook*) remote_host="desktop" ;;
*) remote_host="macbook" ;;
esac

remote_total=0
remote_cache="/tmp/tmux-claude-spend-remote-${uid}"
remote_ttl=30

if [ -n "$remote_host" ] && [ -f "$remote_cache" ]; then
  remote_age=$((now - $(head -1 "$remote_cache")))
  if [ "$remote_age" -lt "$remote_ttl" ]; then
    remote_total=$(sed -n '2p' "$remote_cache")
    remote_total=${remote_total:-0}
  fi
fi

# Fetch fresh remote value if cache is stale
if [ -n "$remote_host" ] && { [ ! -f "$remote_cache" ] || [ "$remote_age" -ge "$remote_ttl" ]; }; then
  remote_val=$(ssh -o ConnectTimeout=0.5 -o BatchMode=yes -o StrictHostKeyChecking=no \
    "$remote_host" '~/.config/tmux/scripts/claude_spend.sh --local' 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$remote_val" ]; then
    remote_total="$remote_val"
  fi
  # Cache even on failure (avoids retrying every 10s)
  printf '%s\n%s' "$now" "$remote_total" >"$remote_cache"
fi

total=$(awk "BEGIN{printf \"%.2f\", $local_total + $remote_total}")

if [ "$total" = "0.00" ]; then
  result=""
else
  result="󱜙 \$${total}"
fi

printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
