function manage_sessions -d "Navigate to an existing session"
  set session_names (tmux list-sessions -F "#{session_name}")
  tmux set-option -p @disable_vertical_pane_navigation yes
  set selected_session (printf "%s\n" $session_names | fzf --prompt "Session: " --preview "fish -c 'preview_session {}'")
  tmux set-option -p -u @disable_vertical_pane_navigation
  if test -n "$selected_session"
    tmux switch-client -t $selected_session
  end
end
