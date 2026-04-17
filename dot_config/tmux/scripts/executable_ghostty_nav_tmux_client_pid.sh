#!/bin/sh
# Print the tmux client PID that currently has focus on this pane.
# Usage: ghostty_nav_tmux_client_pid.sh [pane_id]

log_error() {
    printf '%s [ghostty_nav_tmux_client_pid] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

[ -n "${TMUX:-}" ] || {
    log_error "TMUX environment variable is missing"
    exit 1
}

target_pane="${1:-${TMUX_PANE:-}}"
if [ -z "$target_pane" ]; then
    target_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null)"
fi
[ -n "$target_pane" ] || {
    log_error "unable to resolve target tmux pane"
    exit 1
}

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
'' | *[!0-9]*)
    log_error "resolved invalid client pid: $client_pid for pane $target_pane"
    exit 1
    ;;
esac

printf '%s\n' "$client_pid"
