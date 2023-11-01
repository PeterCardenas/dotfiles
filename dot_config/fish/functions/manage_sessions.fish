function manage_sessions -d "Navigate to an existing session"
  set session_names (tmux list-sessions -F "#{session_name}")
  set selected_session (printf "%s\n" $session_names | fzf --prompt "Session: " --preview "fish -c 'preview_session {}'")
  if test -n "$selected_session"
    tmux switch-client -t $selected_session
  end
end
