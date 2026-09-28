function herdr_close_workspace --description "Close a workspace and remove linked worktree checkouts"
    set -q HERDR_ACTIVE_WORKSPACE_ID; or return 1

    set -l listing (command herdr worktree list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" 2>/dev/null)
    set -l linked_path
    if test $status -eq 0
        set linked_path (printf '%s\n' "$listing" | jq -r --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.worktrees[] | select(.open_workspace_id == $id and .is_linked_worktree == true and .is_bare != true) | .path')
    end

    if test -n "$linked_path"
        read --prompt-str "Remove linked worktree $linked_path? [y/N] " confirm; or return
        string match --quiet --regex '^[Yy]$' "$confirm"; or return
        command herdr worktree remove --workspace "$HERDR_ACTIVE_WORKSPACE_ID"; and return
        read --prompt-str 'Worktree removal was refused. Force removal? [y/N] ' confirm; or return 1
        string match --quiet --regex '^[Yy]$' "$confirm"; or return 1
        command herdr worktree remove --workspace "$HERDR_ACTIVE_WORKSPACE_ID" --force
        return
    end

    read --prompt-str 'Close workspace? [y/N] ' confirm; or return
    string match --quiet --regex '^[Yy]$' "$confirm"; or return
    command herdr workspace close "$HERDR_ACTIVE_WORKSPACE_ID"
end
