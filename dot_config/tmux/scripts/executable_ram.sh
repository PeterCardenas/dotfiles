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
  total_bytes=$(sysctl -n hw.memsize)
  total_gb=$(((total_bytes + 536870912) / 1073741824))
  page_size=$(sysctl -n hw.pagesize)
  used_bytes=$(vm_stat | awk -v ps="$page_size" '
      /Pages active/              { a = int($3) }
      /Pages wired/               { w = int($4) }
      /occupied by compressor/    { c = int($NF) }
      END { printf "%.0f", (a + w + c) * ps }
    ')
  used_gb=$(((used_bytes + 536870912) / 1073741824))
  usage_pct=$(((used_bytes * 100 + total_bytes / 2) / total_bytes))
  result="${used_gb}G/${total_gb}G"
  ;;
Linux)
  read -r used_mib total_mib <<EOF
$(free -m | awk '/Mem:/ {print $3, $2}')
EOF
  usage_pct=$(((used_mib * 100 + total_mib / 2) / total_mib))
  result=$(free -h | awk '/Mem:/ {gsub(/i/,""); printf "%s/%s", $3, $2}')
  ;;
FreeBSD)
  ps=$(sysctl -n hw.pagesize)
  inactive=$(($(sysctl -n vm.stats.vm.v_inactive_count) * ps))
  free_p=$(($(sysctl -n vm.stats.vm.v_free_count) * ps))
  cache_p=$(($(sysctl -n vm.stats.vm.v_cache_count) * ps))
  total_bytes=$(sysctl -n hw.physmem)
  used_bytes=$((total_bytes - inactive - free_p - cache_p))
  total_gb=$(((total_bytes + 536870912) / 1073741824))
  used_gb=$(((used_bytes + 536870912) / 1073741824))
  usage_pct=$(((used_bytes * 100 + total_bytes / 2) / total_bytes))
  result="${used_gb}G/${total_gb}G"
  ;;
OpenBSD)
  ps=$(pagesize)
  used_pages=$(vmstat -s | awk '/pages active/ {print $1}')
  wired_pages=$(vmstat -s | awk '/pages wired/ {print $1}')
  total_bytes=$(sysctl -n hw.physmem)
  used_bytes=$(((used_pages + wired_pages) * ps))
  total_gb=$(((total_bytes + 536870912) / 1073741824))
  used_gb=$(((used_bytes + 536870912) / 1073741824))
  usage_pct=$(((used_bytes * 100 + total_bytes / 2) / total_bytes))
  result="${used_gb}G/${total_gb}G"
  ;;
esac

case "${usage_pct:-0}" in
'' | *[!0-9]*)
  usage_pct=0
  ;;
esac

result="${result:-0G/0G}"
used_part=${result%%/*}
total_part=${result#*/}
result="#[fg=$(usage_color "$usage_pct")]${used_part}#[fg=#c0caf5]/${total_part}"
printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
