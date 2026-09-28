function herdr_new_worktree --description "Create a sibling Herdr worktree from the default branch"
    set -q HERDR_ACTIVE_WORKSPACE_ID; or return 1

    set -l workspace (command herdr workspace get "$HERDR_ACTIVE_WORKSPACE_ID" 2>/dev/null)
    if test $status -ne 0; or not printf '%s\n' "$workspace" | jq -e '.result.workspace.worktree.is_linked_worktree == true' >/dev/null
        printf '%s\n' 'This workspace is not a linked worktree workspace.' >&2
        read --prompt-str 'Press Enter or Escape to close. ' dismiss
        return 1
    end

    set -l listing (command herdr worktree list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" 2>/dev/null)
    set -l listing_status $status
    set -l checkout
    set -l parent_workspace
    if test $listing_status -eq 0
        set checkout (printf '%s\n' "$listing" | jq -r --arg id "$HERDR_ACTIVE_WORKSPACE_ID" '.result.worktrees[] | select(.open_workspace_id == $id and .is_linked_worktree == true and .is_bare != true) | .path')
        set parent_workspace (printf '%s\n' "$listing" | jq -r '.result.source.source_workspace_id // empty')
    end

    bind escape exit
    if test -z "$checkout"; or test -z "$parent_workspace"
        printf '%s\n' 'This workspace is not a linked worktree.' >&2
        read --prompt-str 'Press Enter or Escape to close. ' dismiss
        return 1
    end

    read --prompt-str 'Branch name: ' branch; or return
    set branch (string trim -- "$branch")
    test -n "$branch"; or return

    set -l base (command git -C "$checkout" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    if test -z "$base"
        for candidate in main master
            if command git -C "$checkout" show-ref --verify --quiet "refs/heads/$candidate"
                set base $candidate
                break
            end
        end
    end
    test -n "$base"; or return 1

    set -l common_dir (command git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    test -n "$common_dir"; or return 1
    set -l worktree_path (path dirname "$common_dir")/(string replace --all / - -- "$branch")

    command herdr worktree create --workspace "$parent_workspace" --branch "$branch" --base "$base" --path "$worktree_path" --focus
end
