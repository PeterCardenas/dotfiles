#!/bin/sh
# Print the tmux client PID that currently has focus on this pane.
# Usage: ghostty_nav_tmux_client_pid.sh [pane_id]

[ -n "${TMUX:-}" ] || exit 1

target_pane="${1:-${TMUX_PANE:-}}"
if [ -z "$target_pane" ]; then
    target_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null)"
fi
[ -n "$target_pane" ] || exit 1

client_pid="$(
    tmux list-clients -F '#{client_pid} #{pane_id}' 2>/dev/null |
        awk -v target="$target_pane" '
            NR == 1 { first = $1 }
            $2 == target { print $1; found = 1; exit }
            END {
                if (!found && NR == 1) {
                    print first
                }
            }
        '
)"

case "$client_pid" in
'' | *[!0-9]*) exit 1 ;;
esac

printf '%s\n' "$client_pid"
