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

now=$(date +%s)
spend_dir="${XDG_DATA_HOME:-$HOME/.local/share}/claude-spend"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-spend"
mkdir -p "$spend_dir" "$cache_dir"

# Check main cache (only when producing formatted output)
if [ "$local_only" = false ]; then
  cache="${cache_dir}/tmux-spend"
  if [ -f "$cache" ]; then
    age=$((now - $(head -1 "$cache")))
    if [ "$age" -lt 10 ]; then
      sed -n '2p' "$cache"
      exit 0
    fi
  fi
fi
today=$(date -u +%Y-%m-%d)
daily_file="${spend_dir}/daily-${today}"

# Extract today's cost from a PID file (lines: "YYYY-MM-DD <cost>")
pid_today() {
  awk -v d="$today" '$1 == d { sum += $2 } END { printf "%.4f", sum }' "$1" 2>/dev/null
}

# Roll all entries from a PID file into their respective daily files
roll_pid_file() {
  awk '{ sums[$1] += $2 } END { for (d in sums) printf "%s %.4f\n", d, sums[d] }' "$1" 2>/dev/null |
    while read -r day cost; do
      [ -z "$day" ] && continue
      df="${spend_dir}/daily-${day}"
      prev=0
      if [ -f "$df" ]; then
        prev=$(cat "$df" 2>/dev/null)
        prev=${prev:-0}
      fi
      new=$(awk "BEGIN{printf \"%.4f\", $prev + $cost}")
      printf '%s' "$new" >"$df"
    done
}

# Sum live PID files; roll dead ones into their respective daily files
live_total=0
if [ -d "$spend_dir" ]; then
  for f in "$spend_dir"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in daily-*) continue ;; esac
    val=$(pid_today "$f")
    val=${val:-0}
    if kill -0 "$base" 2>/dev/null; then
      # No spend today + file only has old entries → PID was reused; clean up
      if ([ "$val" = "0" ] || [ "$val" = "0.0000" ]) &&
        [ -s "$f" ] && ! grep -q "^${today} " "$f"; then
        roll_pid_file "$f"
        rm -f "$f"
        continue
      fi
      live_total=$(awk "BEGIN{printf \"%.4f\", $live_total + $val}")
    else
      roll_pid_file "$f"
      rm -f "$f"
    fi
  done
fi

# Re-read today's daily aggregate (may have been updated by roll_pid_file)
daily_total=0
if [ -f "$daily_file" ]; then
  daily_total=$(cat "$daily_file" 2>/dev/null)
  daily_total=${daily_total:-0}
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
remote_cache="${cache_dir}/tmux-spend-remote"
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
  remote_val=$(ssh -o ConnectTimeout=1 -o BatchMode=yes -o StrictHostKeyChecking=no \
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
