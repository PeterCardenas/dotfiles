function detach_others --description "Detach all other tmux clients from the current session"
    if not set -q TMUX
        echo "Not in a tmux session"
        return 1
    end

    set -l current_tty (tmux display-message -p '#{client_tty}')

    set -l detached 0

    for client in (tmux list-clients -F '#{client_tty}')
        if test "$client" != "$current_tty"
            tmux detach-client -t "$client"
            set detached (math $detached + 1)
        end
    end

    if test $detached -eq 0
        print_info "No other clients to detach."
    else
        print_info "Detached $detached client(s)."
    end
end
