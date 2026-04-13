#!/usr/bin/env bash
# Daily Claude spend (UTC) from nvim agentic sessions for tmux status bar.
# PID files contain lines of "YYYY-MM-DD <cost>".
# Sums today's (UTC) values from: daily aggregate + live PID files.
# Dead PID files are rolled into the daily aggregate before pruning.
# Caches result for 10s.
export LC_ALL=C

uid=$(id -u)
cache="/tmp/tmux-claude-spend-${uid}"
now=$(date +%s)
if [ -f "$cache" ]; then
  age=$(( now - $(head -1 "$cache") ))
  if [ "$age" -lt 10 ]; then
    sed -n '2p' "$cache"
    exit 0
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
  printf '%s' "$daily_total" > "$daily_file"
fi

total=$(awk "BEGIN{printf \"%.2f\", $daily_total + $live_total}")

if [ "$total" = "0.00" ]; then
  result=""
else
  result="\$${total}"
fi

printf '%s\n%s' "$now" "$result" > "$cache"
printf '%s' "$result"
