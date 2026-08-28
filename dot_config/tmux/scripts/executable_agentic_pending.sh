#!/bin/sh
state_only=false
if [ "$1" = --state ]; then state_only=true; shift; fi
socket=$1; target=$2
if $state_only; then neutral= green= yellow= red= scope=${3:-window}; else neutral=${3:-#c0caf5}; green=${4:-#9ece6a}; yellow=${5:-#e0af68}; red=${6:-#f7768e}; scope=${7:-window}; fi
tmux_cmd() { case $socket in */*) command tmux -S "$socket" "$@" ;; *) command tmux -L "$socket" "$@" ;; esac; }
if [ "$scope" = session ]; then panes=$(tmux_cmd list-panes -s -t "$target" -F '#{pane_id}' 2>/dev/null); else panes=$(tmux_cmd list-panes -t "$target" -F '#{pane_id}' 2>/dev/null); fi
working=0; idle=0
for pane in $panes; do
 marker=$(tmux_cmd show-options -p -v -t "$pane" @agentic_pending 2>/dev/null) || continue
 case "$marker" in
  *:*:*:*:*:*) continue ;;
 esac
 version= pid= start= w= i= extra=
 IFS=: read -r version pid start w i extra <<EOF
$marker
EOF
 [ "$version" = v1 ] && [ -z "$extra" ] || continue
 case "$pid" in ''|*[!0-9]*) continue ;; esac
 case "$start" in ''|*[!0-9]*) continue ;; esac
 case "$w" in 0|[1-9]|[1-9][0-9]*) ;; *) continue ;; esac
 case "$i" in 0|[1-9]|[1-9][0-9]*) ;; *) continue ;; esac
 [ "$w" -le 10000 ] 2>/dev/null && [ "$i" -le 10000 ] 2>/dev/null || continue
 [ -r "/proc/$pid/stat" ] && kill -0 "$pid" 2>/dev/null || continue
 actual=$(awk '{sub(/^[^)]*\) /,""); print $20}' "/proc/$pid/stat" 2>/dev/null)
 [ "$actual" = "$start" ] || continue
 [ "$w" -gt 0 ] && working=$((working+w))
 [ "$i" -gt 0 ] && idle=$((idle+i))
done
if [ "$working" -gt 0 ] && [ "$idle" -gt 0 ]; then classification=mixed
elif [ "$working" -gt 0 ]; then classification=working
elif [ "$idle" -gt 0 ]; then classification=idle
else classification=none
fi
if $state_only; then printf '%s\n' "$classification"; exit 0; fi
case $classification in working) printf '#[fg=%s]' "$green";; mixed) printf '#[fg=%s]' "$yellow";; idle) printf '#[fg=%s]' "$red";; *) printf '#[fg=%s]' "$neutral";; esac
