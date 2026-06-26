function manage_sessions -d "Navigate to an existing session"
    printf '\e[5 q' # Set cursor shape to blinking bar
    set -l current_session (tmux display-message -p '#{session_name}')
    # Sort sessions by last activity, with most recent first.
    set -l session_activities (tmux list-sessions -F "#{session_name}|#{session_activity}" | sort -t "|" -k2 -r)
    # Exclude the current session.
    set -l session_names (printf "%s\n" $session_activities | cut -d "|" -f 1 | string match -v -e "$current_session")
    set selected_session (printf "%s\n" $session_names | fzf --cycle --reverse --with-shell "fish -c" --prompt "Session: " --preview "preview_session {}")
    if test -n "$selected_session"
        tmux switch-client -t $selected_session
    end
end
