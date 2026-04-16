#!/bin/sh
# Sync Ghostty navigation from tmux, local or over SSH.
# Usage: ghostty_nav_tmux.sh [directions]
#   directions: comma-separated list (h,j,k,l), "all", or empty to disable all

directions="${1:-}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

client_pid_script="$script_dir/ghostty_nav_tmux_client_pid.sh"
remote_pid_script="$script_dir/ghostty_nav_remote.sh"

if [ ! -x "$client_pid_script" ] && [ -x "$script_dir/executable_ghostty_nav_tmux_client_pid.sh" ]; then
    client_pid_script="$script_dir/executable_ghostty_nav_tmux_client_pid.sh"
fi
if [ ! -x "$remote_pid_script" ] && [ -x "$script_dir/executable_ghostty_nav_remote.sh" ]; then
    remote_pid_script="$script_dir/executable_ghostty_nav_remote.sh"
fi

tmux_client_pid="$("$client_pid_script" 2>/dev/null)"

ssh_connection="${SSH_CONNECTION:-}"
if [ -n "$ssh_connection" ]; then
    [ "$(uname)" = "Linux" ] || exit 0
    remote_start_pid="$("$remote_pid_script" 2>/dev/null)"
    case "$remote_start_pid" in
    '' | *[!0-9]*) exit 0 ;;
    esac
    ssh -o ConnectTimeout=2 macbook "fish -c 'ghostty_nvim_nav \"$directions\" \"$remote_start_pid\"'" >/dev/null 2>&1 || true
    exit 0
fi

case "$tmux_client_pid" in
'' | *[!0-9]*) exit 0 ;;
esac

[ "$(uname)" = "Linux" ] && exit 0

fish -c "ghostty_nvim_nav \"$directions\" \"$tmux_client_pid\"" 2>/dev/null || true
