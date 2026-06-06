#!/usr/bin/env bash
# Cross-platform root filesystem free space remaining.
export LC_ALL=C

cache="/tmp/tmux-disk-$(id -u)"
now=$(date +%s)
if [ -f "$cache" ]; then
  age=$((now - $(head -1 "$cache")))
  if [ "$age" -lt 2 ]; then
    tail -1 "$cache"
    exit 0
  fi
fi

gib=$((1024 * 1024 * 1024))

avail_color() {
  local avail_bytes="$1"

  if [ "$avail_bytes" -lt $((100 * gib)) ]; then
    printf '#f7768e'
  elif [ "$avail_bytes" -lt $((250 * gib)) ]; then
    printf '#ff9e64'
  elif [ "$avail_bytes" -lt $((500 * gib)) ]; then
    printf '#e0af68'
  else
    printf '#9ece6a'
  fi
}

mount_point="/"
df_flags=(-h)

case "$(uname -s)" in
Darwin)
  df_flags=(-H)
  avail_bytes=$(df -k "$mount_point" | awk 'NR==2 {print $4 * 1024}')
  ;;
Linux)
  avail_bytes=$(df -B1 --output=avail "$mount_point" | tail -1)
  ;;
*)
  avail_bytes=$(df -k "$mount_point" | awk 'NR==2 {print $4 * 1024}')
  ;;
esac

read -r avail <<EOF
$(df "${df_flags[@]}" "$mount_point" | awk 'NR==2 {
  gsub(/i/, "", $4)
  print $4
}')
EOF

case "${avail_bytes:-0}" in
'' | *[!0-9]*)
  avail_bytes=0
  ;;
esac

result="#[fg=$(avail_color "$avail_bytes")]${avail:-0}"
printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
