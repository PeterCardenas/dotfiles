function manage_sessions -d "Navigate to an existing session"
  # Sort sessions by last activity, with most recent first.
  set session_activities (tmux list-sessions -F "#{session_name}|#{session_activity}" | sort -t "|" -k2 -r)
  # Exclude the current session.
  set session_activities $session_activities[2..-1]
  # Extract the session names.
  set session_names (printf "%s\n" $session_activities | cut -d "|" -f 1)
  set selected_session (printf "%s\n" $session_names | fzf --prompt "Session: " --preview "fish -c 'preview_session {}'")
  if test -n "$selected_session"
    tmux switch-client -t $selected_session
  end
end
