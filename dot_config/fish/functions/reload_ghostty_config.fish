function reload_ghostty_config --description "Reload ghostty configuration by sending USR2 signal"
    set -l ghostty_pid (ps -eo pid,comm | awk '$2 == "/Applications/Ghostty.app/Contents/MacOS/ghostty" {print $1}')

    if test -z "$ghostty_pid"
        return 1
    end

    kill -USR2 $ghostty_pid
    return $status
end
