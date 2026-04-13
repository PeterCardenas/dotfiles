function reload_ghostty_config --description "Reload ghostty configuration by sending USR2 signal"
    if not test "$TERM" = xterm-ghostty; or set -q TMUX; or set -q SSH_CONNECTION
        print_error "This function is only intended to be used in ghostty sessions"
        return 1
    end
    # Get all ghostty process PIDs
    set -l ghostty_pids (ps -eo pid,comm | awk '$2 ~ /ghostty$/ {print $1}')

    if test -z "$ghostty_pids"
        print_error "No ghostty processes found"
        return 1
    end

    # Walk up the parent process chain to find which ghostty instance we're running in
    set -l current_pid $fish_pid
    while test $current_pid -gt 1
        # Check if current_pid matches any ghostty PID
        for gpid in $ghostty_pids
            if test $current_pid -eq $gpid
                # Found the ghostty instance that owns this shell
                print_info "Reloading ghostty config (PID: $gpid)"
                kill -USR2 $gpid
                set -l kill_status $status
                if test $kill_status -ne 0
                    print_error "Failed to send USR2 signal to ghostty (PID: $gpid)"
                end
                return $kill_status
            end
        end

        # Get parent PID
        set current_pid (ps -o ppid= -p $current_pid 2>/dev/null | string trim)

        # Break if we couldn't get parent (reached init or error)
        if test -z "$current_pid"
            print_error "Could not find parent ghostty process"
            return 1
        end
    end
    print_error "Could not find owning ghostty instance"
    return 1
end
