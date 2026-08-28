function manage_sessions -d "Navigate to an existing session"
    printf '\e[5 q'
    test -n "$TMUX"; or return 1
    set -l tmux_socket (string split ',' -- $TMUX)[1]
    set -l socket_args
    if string match -q '*/*' -- $tmux_socket
        set socket_args -S $tmux_socket
    else
        set socket_args -L $tmux_socket
    end
    tmux $socket_args has-session 2>/dev/null; or return 1
    set -l current_session (tmux $socket_args display-message -p '#{session_name}')
    set -l helper ~/.config/tmux/scripts/agentic_pending.sh
    set -l names (tmux $socket_args list-sessions -F '#{session_name}')
    set -l activities
    set -l ordered_names
    for name in $names
        test "$name" = "$current_session"; and continue
        set -a activities (tmux $socket_args display-message -p -t "$name" '#{session_activity}')
        set -a ordered_names "$name"
    end
    # Sort parallel arrays numerically so names never pass through a delimiter.
    set -l count (count $ordered_names)
    if test $count -gt 1
        for i in (seq 2 $count)
            set -l j $i
            while test $j -gt 1; and test $activities[$j] -gt $activities[(math $j - 1)]
                set -l tmp $activities[$j]
                set activities[$j] $activities[(math $j - 1)]
                set activities[(math $j - 1)] $tmp
                set tmp $ordered_names[$j]
                set ordered_names[$j] $ordered_names[(math $j - 1)]
                set ordered_names[(math $j - 1)] $tmp
                set j (math $j - 1)
            end
        end
    end
    set -l rows
    for i in (seq 1 $count)
        set -l name $ordered_names[$i]
        set -l state ($helper --state $tmux_socket "$name" session)
        set -l display $name
        switch $state
            case working; set display (printf '\e[38;2;158;203;106m%s\e[0m' "$name")
            case mixed; set display (printf '\e[38;2;224;174;104m%s\e[0m' "$name")
            case idle; set display (printf '\e[38;2;247;118;142m%s\e[0m' "$name")
        end
        set -a rows (printf '%s\t%s' "$name" "$display")
    end
    set -l selection (printf '%s\n' $rows | fzf --ansi --cycle --reverse --delimiter='\t' --with-nth='2..' --with-shell "fish -c" --prompt "Session: " --preview "preview_session {1}")
    set -l selected_session (string split -m 1 \t -- "$selection")[1]
    if test -n "$selected_session"
        tmux $socket_args switch-client -t "$selected_session"
    end
end
