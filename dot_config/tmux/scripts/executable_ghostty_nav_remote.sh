#!/bin/sh
# Resolve the remote ET client PID on macOS for this tmux client.
# Usage: ghostty_nav_remote.sh [tmux_client_pid]
[ "$(uname)" = "Linux" ] || exit 0

log_error() {
    printf '%s [ghostty_nav_remote] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

ssh_connection="${SSH_CONNECTION:-}"

[ -n "$ssh_connection" ] || {
    log_error "SSH_CONNECTION is not set"
    exit 1
}

set -- $ssh_connection
ssh_client_port="$2"
[ -n "$ssh_client_port" ] || {
    log_error "failed to parse SSH client port from SSH_CONNECTION='$ssh_connection'"
    exit 0
}

case "$ssh_client_port" in
'' | *[!0-9]*)
    log_error "parsed non-numeric SSH client port: $ssh_client_port"
    exit 0
    ;;
esac

# Find the local etserver process that owns this session's local SSH tunnel.
et_pid="$(lsof -nP -iTCP:"$ssh_client_port" -sTCP:ESTABLISHED 2>/dev/null | awk '
NR > 1 && $9 ~ /->/ && $9 ~ /:22$/ {
    print $2
    exit
}
')"

# Map that etserver process to its external ET connection (port 2022, the default).
et_external_port=""
if [ -n "$et_pid" ]; then
    et_external_port="$(lsof -nP -a -p "$et_pid" -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk '
    NR > 1 && $9 ~ /->/ && $9 ~ /:2022$/ {
        split($9, conn, "->")
        local = conn[1]
        n = split(local, parts, ":")
        print parts[n]
        exit
    }
    ')"
fi

# Fallback when process-level socket ownership is unavailable:
# if exactly one ET connection exists, use it.
if [ -z "$et_external_port" ]; then
    et_external_port_candidates="$(ss -tn | awk '
    $1 == "ESTAB" && $5 ~ /:2022$/ {
        split($4, parts, ":")
        print parts[length(parts)]
    }
    ')"
    et_external_count="$(printf '%s\n' "$et_external_port_candidates" | awk 'NF { c += 1 } END { print c + 0 }')"
    [ "$et_external_count" -eq 1 ] || {
        log_error "fallback found $et_external_count ET candidates (expected 1)"
        exit 0
    }
    et_external_port="$(printf '%s\n' "$et_external_port_candidates" | awk 'NF { print; exit }')"
fi

[ -n "$et_external_port" ] || {
    log_error "unable to resolve ET external port"
    exit 0
}

case "$et_external_port" in
'' | *[!0-9]*)
    log_error "resolved invalid external port: $et_external_port"
    exit 1
    ;;
esac

# Resolve the ET client PID on macOS, then crawl up to owning Ghostty PID there.
remote_start_pid=""
if ! remote_start_pid="$(ssh -o ConnectTimeout=2 macbook "lsof -tiTCP:$et_external_port -sTCP:ESTABLISHED | awk 'NR == 1 { print; exit }'" 2>/dev/null)"; then
    log_error "failed SSH lookup for external port: $et_external_port"
fi

case "$remote_start_pid" in
'' | *[!0-9]*)
    log_error "resolved invalid remote start pid: $remote_start_pid (port=$et_external_port)"
    exit 1
    ;;
esac

printf '%s\n' "$remote_start_pid"
