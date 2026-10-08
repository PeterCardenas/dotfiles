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
            if herdr_is_unregistered_worktree "$checkout" "$repo_key"
                set -l confirm (herdr_popup_read "Git no longer lists linked checkout $checkout. Force delete its remaining files and close workspace? [y/N]"); or return 1
                if string match --quiet --regex '^[Yy]$' "$confirm"
                    herdr_purge_unregistered_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$checkout" "$repo_key"; and return 0
                end
                herdr_popup_read 'Checkout was not removed; press Enter to dismiss.' >/dev/null
                return 1
            end
            if herdr_can_remove_pointerless_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$checkout" "$repo_key"
                set -l confirm (herdr_popup_read "Git no longer lists linked checkout $checkout. Permanently delete all remaining checkout files and close workspace? [y/N]"); or return 1
                string match --quiet --regex '^[Yy]$' "$confirm"; or return 1
                herdr_remove_pointerless_worktree "$HERDR_ACTIVE_WORKSPACE_ID" "$checkout" "$repo_key"; and return 0
                herdr_popup_read 'Removal failed; press Enter to dismiss.' >/dev/null
                return 1
            end
            printf '%s\n' 'Cannot safely close linked workspace; checkout identity could not be verified.' >&2
            herdr_popup_read 'Removal failed; press Enter to dismiss.' >/dev/null
            return 1
        end
    end

    if test -n "$linked_path"
        set -l confirm (herdr_popup_read "Force-remove linked worktree $linked_path? [y/N] This terminates its pane processes and permanently deletes uncommitted or ignored files; unsaved work will be lost."); or return
        string match --quiet --regex '^[Yy]$' "$confirm"; or return
        set -l removal (command herdr worktree remove --workspace "$HERDR_ACTIVE_WORKSPACE_ID" --force 2>&1)
        set -l removal_status $status
        printf '%s\n' "$removal" >&2
        if test $removal_status -eq 0
            return 0
        end
        set -l error_message (herdr_worktree_removal_error_message "$removal")
        herdr_popup_read "Worktree removal failed: $error_message. Press Enter to continue." >/dev/null; or return $removal_status
        set -l repo_key (printf '%s\n' "$listing" | jq -r '.result.source.repo_key // empty')
        herdr_recover_failed_worktree_removal "$HERDR_ACTIVE_WORKSPACE_ID" "$linked_path" "$repo_key" "$error_message"; and return 0
        herdr_popup_read 'Recovery did not complete. The checkout or workspace may have changed; inspect their current state before retrying. Press Enter to dismiss.' >/dev/null
        return $removal_status
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
    # Workspace metadata cannot prove ownership once Git has removed the .git pointer.
    set -l pointer (command head -n 1 -- "$checkout/.git" 2>/dev/null); or return 1
    string match --quiet -- "gitdir: $repo_key/worktrees/*" "$pointer"; or return 1
    set -l registered (command git -C "$repo_key" worktree list --porcelain 2>/dev/null); or return 1
    if contains -- "worktree $checkout" $registered
        printf '%s\n' 'Checkout is still registered with Git; refusing filesystem deletion.' >&2
        return 1
    end
    return 0
end

function herdr_worktree_removal_error_message --argument-names output
    set -l message (printf '%s\n' "$output" | jq -er '.error.message | strings | select(length > 0)' 2>/dev/null)
    if test $status -eq 0
        printf '%s\n' "$message"
    else if not printf '%s\n' "$output" | jq -e . >/dev/null 2>&1
        printf '%s\n' "$output"
    else
        printf '%s\n' 'Herdr returned an error without a message.'
    end
end

function herdr_recover_failed_worktree_removal --argument-names workspace_id checkout repo_key error_message
    if herdr_is_unregistered_worktree "$checkout" "$repo_key"
        set -l confirm (herdr_popup_read "Git has unregistered checkout $checkout but files remain. Git removal cannot be relied on to delete them; a concurrent writer can cause Directory not empty. Force delete remaining files and close workspace? [y/N]"); or return 1
        string match --quiet --regex '^[Yy]$' "$confirm"; or return 1
        herdr_purge_unregistered_worktree "$workspace_id" "$checkout" "$repo_key"
        return $status
    end

    if herdr_can_remove_pointerless_worktree "$workspace_id" "$checkout" "$repo_key"
        set -l confirm (herdr_popup_read "Git has unregistered checkout $checkout but files remain. Git removal cannot be relied on to delete them; a concurrent writer can cause Directory not empty. Permanently delete all remaining checkout files and close workspace? [y/N]"); or return 1
        string match --quiet --regex '^[Yy]$' "$confirm"; or return 1
        herdr_remove_pointerless_worktree "$workspace_id" "$checkout" "$repo_key"
        return $status
    end
    printf '%s\n' "Recovery was refused after: $error_message" >&2
    return 1
end

function herdr_can_remove_pointerless_worktree --argument-names workspace_id checkout repo_key
    if test -z "$checkout"; or test -z "$repo_key"; or not string match --quiet '/*' -- "$checkout"; or not string match --quiet '/*' -- "$repo_key"; or test "$checkout" = "$repo_key"; or test -L "$checkout"; or not test -d "$checkout"; or test -e "$checkout/.git"; or test -L "$checkout/.git"; or test -L "$repo_key"; or not test -d "$repo_key"
        return 1
    end

    set -l canonical_checkout (command realpath -- "$checkout" 2>/dev/null); or return 1
    set -l canonical_repo (command realpath -- "$repo_key" 2>/dev/null); or return 1
    if test "$canonical_checkout" != "$checkout"; or test "$canonical_repo" != "$repo_key"; or test (command dirname -- "$checkout") != (command dirname -- "$repo_key")
        return 1
    end

    set -l is_bare (command git -C "$repo_key" rev-parse --is-bare-repository 2>/dev/null); or return 1
    test "$is_bare" = true; or return 1

    set -l workspaces (command herdr workspace list 2>/dev/null); or return 1
    printf '%s\n' "$workspaces" | jq -e --arg id "$workspace_id" --arg checkout "$checkout" --arg repo "$repo_key" '[.result.workspaces[]? | select(.workspace_id == $id)] as $rows | ($rows | length) == 1 and ($rows[0].worktree.is_linked_worktree == true and $rows[0].worktree.checkout_path == $checkout and $rows[0].worktree.repo_key == $repo)' >/dev/null; or return 1

    set -l registered (command git -C "$repo_key" worktree list --porcelain 2>/dev/null); or return 1
    if contains -- "worktree $checkout" $registered
        printf '%s\n' 'Checkout is still registered with Git; refusing filesystem deletion.' >&2
        return 1
    end
    return 0
end

function herdr_remove_pointerless_worktree --argument-names workspace_id checkout repo_key
    herdr_can_remove_pointerless_worktree "$workspace_id" "$checkout" "$repo_key"; or return 1
    command rm -rf -- "$checkout"; or return 1
    test ! -e "$checkout"; or return 1
    command herdr workspace close "$workspace_id"
end

function herdr_purge_unregistered_worktree --argument-names workspace_id checkout repo_key
    herdr_is_unregistered_worktree "$checkout" "$repo_key"; or return 1
    command rm -rf -- "$checkout"; or return 1
    test ! -e "$checkout"; or return 1
    command herdr workspace close "$workspace_id"
end
