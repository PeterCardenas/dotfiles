function herdr_new_worktree --description "Create a Herdr worktree in a chosen repository group"
    set -q HERDR_ACTIVE_WORKSPACE_ID; or return 1

    set -l workspaces (command herdr workspace list 2>/dev/null); or return 1
    # A Git checkout alone is not a sidebar group; only bases with linked children qualify.
    set -l group_ids (printf '%s\n' "$workspaces" | jq -r '
        .result.workspaces as $all | $all[] | . as $base
        | select(.worktree.is_linked_worktree == false and .worktree.repo_key != null)
        | select(any($all[]; .worktree.repo_key == $base.worktree.repo_key and .worktree.is_linked_worktree == true))
        | .workspace_id')
    set -l groups
    for id in $group_ids
        set -l listing (command herdr worktree list --workspace "$id" 2>/dev/null); or continue
        set -l checkout (printf '%s\n' "$listing" | jq -r '.result.source.source_checkout_path // empty')
        test -n "$checkout"; or continue
        set -l label (printf '%s\n' "$workspaces" | jq -r --arg id "$id" '.result.workspaces[] | select(.workspace_id == $id) | .label')
        set -a groups (printf '%s\t%s — %s' "$id" "$label" "$checkout")
    end

    set -l active_listing (command herdr worktree list --workspace "$HERDR_ACTIVE_WORKSPACE_ID" 2>/dev/null)
    set -l default_group (printf '%s\n' "$active_listing" | jq -r '.result.source.source_workspace_id // empty' 2>/dev/null)
    if contains -- "$default_group" $group_ids
        set groups (string match -- "$default_group"\t'*' $groups) (string match -v -- "$default_group"\t'*' $groups)
    else
        set -p groups (printf '\tChoose a group')
    end
    printf '%s\n' 'Group: choose a repository (Enter to continue; Escape to cancel)' >&2
    set -l choice (printf '%s\n' $groups | fzf --no-sort --layout=reverse --delimiter='\t' --with-nth=2 --prompt='Group> '); or return 1
    set -l group (string match -r '^[^\t]+' -- "$choice")
    test -n "$group"; or return 1

    set -l listing (command herdr worktree list --workspace "$group" 2>/dev/null); or return 1
    set -l checkout (printf '%s\n' "$listing" | jq -r '.result.source.source_checkout_path // empty')
    test -n "$checkout"; or return 1
    set -l branch (herdr_popup_read 'Branch name:'); or return
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

    command herdr worktree create --workspace "$group" --branch "$branch" --base "$base" --path "$worktree_path" --focus
end
