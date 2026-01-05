function reload_ghostty_config --description "Reload ghostty configuration by sending USR2 signal"
    # Get all ghostty process PIDs
    set -l ghostty_pids (ps -eo pid,comm | awk '$2 ~ /ghostty$/ {print $1}')

    if test -z "$ghostty_pids"
        return 1
    end

    # Walk up the parent process chain to find which ghostty instance we're running in
    set -l current_pid $fish_pid
    while test $current_pid -gt 1
        # Check if current_pid matches any ghostty PID
        for gpid in $ghostty_pids
            if test $current_pid -eq $gpid
                # Found the ghostty instance that owns this shell
                kill -USR2 $gpid
                return $status
            end
        end

        # Get parent PID
        set current_pid (ps -o ppid= -p $current_pid 2>/dev/null | string trim)

        # Break if we couldn't get parent (reached init or error)
        if test -z "$current_pid"
            return 1
        end
    end
    return 1
end
