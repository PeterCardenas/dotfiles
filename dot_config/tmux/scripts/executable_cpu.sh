#!/usr/bin/env bash
# Cross-platform CPU usage percentage.
# Uses iostat (preferred) with fallbacks to top/ps.
# Caches results for 2s since iostat needs ~1s to sample.
export LC_ALL=C

cache="/tmp/tmux-cpu-$(id -u)"
now=$(date +%s)
if [ -f "$cache" ]; then
  age=$((now - $(head -1 "$cache")))
  if [ "$age" -lt 2 ]; then
    tail -1 "$cache"
    exit 0
  fi
fi

usage_color() {
  local usage="$1"

  if [ "$usage" -ge 80 ]; then
    printf '#f7768e'
  elif [ "$usage" -ge 65 ]; then
    printf '#ff9e64'
  elif [ "$usage" -ge 40 ]; then
    printf '#e0af68'
  else
    printf '#9ece6a'
  fi
}

case "$(uname -s)" in
Darwin)
  # macOS: iostat reports cpu as us/sy/id columns; idle is column 6
  val=$(iostat -c 2 disk0 | sed '/^\s*$/d' | tail -1 | awk '{printf "%.0f", 100-$6}')
  ;;
Linux)
  if command -v iostat &>/dev/null; then
    val=$(iostat -c 1 2 | sed '/^\s*$/d' | tail -1 | awk '{printf "%.0f", 100-$NF}')
  else
    # Fallback: top in batch mode, 2 samples
    val=$(top -bn2 -d 0.01 2>/dev/null | grep '[C]pu(s)' | tail -1 |
      sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{printf "%.0f", 100-$1}')
  fi
  ;;
FreeBSD | OpenBSD)
  val=$(iostat -c 2 2>/dev/null | sed '/^\s*$/d' | tail -1 | awk '{printf "%.0f", 100-$NF}')
  ;;
esac

case "${val:-0}" in
'' | *[!0-9]*)
  val=0
  ;;
esac

result="#[fg=$(usage_color "$val")]${val}%"
printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
