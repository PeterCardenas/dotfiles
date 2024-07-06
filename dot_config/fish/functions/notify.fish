function notify -d "Send notifications via terminal escape sequences" -a title -a message
    # Add the commandline to the message or title if not provided.
    if test -z "$title"
        set title (status current-commandline)
        set message "Command completed"
    end
    if test -z "$message"
        set message "Command completed: $(status current-commandline)"
    end
    set -l osc_prefix
    if set -q TMUX
        # Assume that tmux sessions in ssh sessions are nested.
        if set -q SSH_CONNECTION
            set osc_prefix "\x1bPtmux;\x1b\x1bPtmux;\x1b\x1b\x1b\x1b"
        else
            set osc_prefix "\x1bPtmux;\x1b\x1b"
        end
    else
        set osc_prefix "\x1b"
    end
    set -l notify_prefix "$osc_prefix]777;notify;"
    set -l osc_suffix
    if set -q TMUX
        if set -q SSH_CONNECTION
            set osc_suffix "\a\x1b\x1b\\\\\x1b\\"
        else
            set osc_suffix "\a\x1b\\"
        end
    else
        set osc_suffix "\x1b\\"
    end
    set -l sequence "$notify_prefix$title;$message$osc_suffix"
    printf $sequence
end
