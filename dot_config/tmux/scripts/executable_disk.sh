#!/usr/bin/env bash
# Cross-platform free space for / plus any local filesystem mounted under $HOME.
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

# -P keeps one line per mount and identical columns on Linux and macOS; -l skips
# network mounts that can hang the status bar.
result=$(df -kPl 2>/dev/null | awk -v home="$HOME" '
  function human(kib, units, i) {
    units = "KMGTP"
    for (i = 1; kib >= 1024 && i < length(units); i++) kib /= 1024
    return sprintf(kib < 10 && i > 1 ? "%.1f%s" : "%.0f%s", kib, substr(units, i, 1))
  }
  function color(kib, gib) {
    gib = kib / 1048576
    if (gib < 50) return "#f7768e"
    if (gib < 250) return "#ff9e64"
    if (gib < 500) return "#e0af68"
    return "#9ece6a"
  }
  NR > 1 {
    # Mount points may contain spaces, so drop the five leading columns instead of using $NF.
    mount = $0
    for (i = 1; i <= 5; i++) sub(/^[^ ]+ +/, "", mount)
    if (mount == "/") label = "/"
    else if (index(mount, home "/") == 1) label = "~/" substr(mount, length(home) + 2)
    else next
    out = out (out == "" ? "" : " ") "#[fg=#c0caf5]" label ":#[fg=" color($4) "]" human($4)
  }
  END { print out }
')

printf '%s\n%s' "$now" "$result" >"$cache"
printf '%s' "$result"
