function preview_session -d "Preview tmux session" -a session_name
    tmux capture-pane -ep -t $session_name
    # set active_pane_index (tmux display-message -t $session_name -p '#{pane_index}')
    # set pane_indices (tmux list-panes -t $session_name -F '#{pane_index}')
    # for pane_index in $pane_indices
    #   tmux capture-pane -ep -t $session_name.$pane_index
    # end
end
