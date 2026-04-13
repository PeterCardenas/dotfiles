#!/usr/bin/env bash
# Cross-platform RAM usage (used/total).
# macOS: vm_stat page arithmetic (avoids system_profiler which hangs ~10s).
# Linux: free. BSD: sysctl counters.
export LC_ALL=C

cache="/tmp/tmux-ram-$(id -u)"
now=$(date +%s)
if [ -f "$cache" ]; then
  age=$((now - $(head -1 "$cache")))
  if [ "$age" -lt 2 ]; then
    tail -1 "$cache"
    exit 0
  fi
fi

case "$(uname -s)" in
Darwin)
  total_gb=$(($(sysctl -n hw.memsize) / 1073741824))
  page_size=$(sysctl -n hw.pagesize)
  used_gb=$(vm_stat | awk -v ps="$page_size" '
      /Pages active/              { a = int($3) }
      /Pages wired/               { w = int($4) }
      /occupied by compressor/    { c = int($NF) }
      END { printf "%.0f", (a + w + c) * ps / 1073741824 }
    ')
  result="${used_gb}G/${total_gb}G"
  ;;
Linux)
  result=$(free -h | awk '/Mem:/ {gsub(/i/,""); printf "%s/%s", $3, $2}')
  ;;
FreeBSD)
  ps=$(sysctl -n hw.pagesize)
  inactive=$(($(sysctl -n vm.stats.vm.v_inactive_count) * ps))
  free_p=$(($(sysctl -n vm.stats.vm.v_free_count) * ps))
  cache_p=$(($(sysctl -n vm.stats.vm.v_cache_count) * ps))
  total=$(($(sysctl -n hw.physmem) / 1073741824))
  used=$(((total * 1073741824 - inactive - free_p - cache_p) / 1073741824))
  result="${used}G/${total}G"
  ;;
OpenBSD)
  ps=$(pagesize)
  used_pages=$(vmstat -s | awk '/pages active/ {print $1}')
  wired_pages=$(vmstat -s | awk '/pages wired/ {print $1}')
  total=$(($(sysctl -n hw.physmem) / 1073741824))
  used=$(((used_pages + wired_pages) * ps / 1073741824))
  result="${used}G/${total}G"
  ;;
esac

result="${result:-0G/0G}"
printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
