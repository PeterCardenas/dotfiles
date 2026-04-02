function detach_others --description "Detach all other tmux clients from the current session"
    if not set -q TMUX
        echo "Not in a tmux session"
        return 1
    end

    set -l current_tty (tmux display-message -p '#{client_tty}')

    for client in (tmux list-clients -F '#{client_tty}')
        if test "$client" != "$current_tty"
            tmux detach-client -t "$client"
        end
    end
end
