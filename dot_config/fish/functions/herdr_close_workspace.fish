function herdr_close_workspace --description "Close a workspace and remove linked worktree checkouts"
    set -q HERDR_ACTIVE_WORKSPACE_ID; or return 1

    set -l listing (command herdr worktree list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" 2>/dev/null)
    set -l linked_path
    if test $status -eq 0
        set linked_path (printf '%s\n' "$listing" | jq -r --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.worktrees[]? | select(.open_workspace_id == $id and .is_linked_worktree == true and .is_bare != true) | .path // empty')
    end

    if test -z "$linked_path"
        # A failed or incomplete Git lookup must not turn a linked checkout into a plain close.
        set -l workspaces (command herdr workspace list 2>/dev/null); or return 1
        set -l kind (printf '%s\n' "$workspaces" | jq -er --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.workspaces[] | select(.workspace_id == $id) | if .worktree.is_linked_worktree == true then "linked" else "plain" end'); or return 1
        if test "$kind" = linked
            set -l checkout (printf '%s\n' "$workspaces" | jq -r --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.workspaces[] | select(.workspace_id == $id) | .worktree.checkout_path // empty')
            set -l repo_key (printf '%s\n' "$workspaces" | jq -r --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.workspaces[] | select(.workspace_id == $id) | .worktree.repo_key // empty')
            if not herdr_is_unregistered_worktree "$checkout" "$repo_key"
                printf '%s\n' 'Cannot safely purge linked checkout; workspace was not closed.' >&2
                herdr_popup_read 'Removal failed; press Enter to dismiss.' >/dev/null
                return 1
            end
            set -l confirm (herdr_popup_read "Git no longer lists linked checkout $checkout. Force delete its remaining files and close workspace? [y/N]"); or return 1
            if string match --quiet --regex '^[Yy]$' "$confirm"
                herdr_purge_unregistered_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$checkout" "$repo_key"; and return 0
            end
            herdr_popup_read 'Checkout was not removed; press Enter to dismiss.' >/dev/null
            return 1
        end
    end

    if test -n "$linked_path"
        set -l confirm (herdr_popup_read "Remove linked worktree $linked_path? [y/N]"); or return
        string match --quiet --regex '^[Yy]$' "$confirm"; or return
        set -l removal (command herdr worktree remove --workspace "$HERDR_ACTIVE_WORKSPACE_ID" 2>&1)
        set -l removal_status $status
        printf '%s\n' "$removal" >&2
        if test $removal_status -eq 0
            return 0
        end
        if not printf '%s\n' "$removal" | jq -e '.error.code == "dirty_worktree_requires_force"' >/dev/null 2>&1
            set -l repo_key (printf '%s\n' "$listing" | jq -r '.result.source.repo_key // empty')
            if herdr_is_unregistered_worktree "$linked_path" "$repo_key"
                set confirm (herdr_popup_read "Git no longer lists linked checkout $linked_path. Force delete remaining files and close workspace? [y/N]"); or return 1
                if string match --quiet --regex '^[Yy]$' "$confirm"
                    herdr_purge_unregistered_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$linked_path" "$repo_key"; and return 0
                end
            end
            herdr_popup_read 'Removal failed; press Enter to dismiss.' >/dev/null
            return $removal_status
        end
        set confirm (herdr_popup_read 'Dirty worktree removal was refused. Force removal? [y/N]'); or return 1
        string match --quiet --regex '^[Yy]$' "$confirm"; or return 1
        set -l forced_removal (command herdr worktree remove --workspace "$HERDR_ACTIVE_WORKSPACE_ID" --force 2>&1)
        set -l force_status $status
        printf '%s\n' "$forced_removal" >&2
        if test $force_status -ne 0
            set -l repo_key (printf '%s\n' "$listing" | jq -r '.result.source.repo_key // empty')
            herdr_purge_unregistered_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$linked_path" "$repo_key"; and return 0
            herdr_popup_read 'Removal failed; press Enter to dismiss.' >/dev/null
        end
        return $force_status
    end

    set -l confirm (herdr_popup_read 'Close workspace? [y/N]'); or return
    string match --quiet --regex '^[Yy]$' "$confirm"; or return
    command herdr workspace close "$HERDR_ACTIVE_WORKSPACE_ID"
end

function herdr_is_unregistered_worktree --argument-names checkout repo_key
    # Git may have removed its worktree registration before failing to delete all files.
    if test -z "$checkout"; or test -z "$repo_key"; or not string match --quiet '/*' -- "$checkout"; or test "$checkout" = "$repo_key"; or test -L "$checkout"
        printf '%s\n' 'Refusing to delete an unverified checkout path.' >&2
        return 1
    end
    set -l pointer (command head -n 1 -- "$checkout/.git" 2>/dev/null); or return 1
    string match --quiet -- "gitdir: $repo_key/worktrees/*" "$pointer"; or return 1
    set -l registered (command git -C "$repo_key" worktree list --porcelain 2>/dev/null); or return 1
    if contains -- "worktree $checkout" $registered
        printf '%s\n' 'Checkout is still registered with Git; refusing filesystem deletion.' >&2
        return 1
    end
    return 0
end

function herdr_purge_unregistered_worktree --argument-names workspace_id checkout repo_key
    herdr_is_unregistered_worktree "$checkout" "$repo_key"; or return 1
    command rm -rf -- "$checkout"; or return 1
    test ! -e "$checkout"; or return 1
    command herdr workspace close "$workspace_id"
end
