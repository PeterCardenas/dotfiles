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
    set -l branch (herdr_popup_read 'Branch name: (empty for detached default commit)'); or return 1
    set branch (string trim -- "$branch")

    set -l base (command git -C "$checkout" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
    if not string match -qr '^origin/.+' -- "$base"
        printf '%s\n' 'Cannot determine origin default branch (origin/HEAD is missing).' >&2
        return 1
    end
    if test -z "$branch"
        set -l confirmation (herdr_popup_read "Use latest $base commit without a branch? [y/N]"); or return 1
        test (string lower -- (string trim -- "$confirmation")) = y; or return 1
    end

    set -l default_name (string replace 'origin/' '' -- "$base")
    command git -C "$checkout" fetch origin "$default_name"; or return 1

    set -l common_dir (command git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    test -n "$common_dir"; or return 1
    set -l worktree_dir (path dirname "$common_dir")
    if test -n "$branch"
        set -l worktree_path "$worktree_dir"/(string replace --all / - -- "$branch")
        command herdr worktree create --workspace "$group" --branch "$branch" --base "$base" --path "$worktree_path" --focus
    else
        # Herdr create invents a branch when --branch is omitted; Git must make the detached checkout.
        set -l default_slug (string replace --all / - -- "$default_name")
        set -l worktree_path (command mktemp -d "$worktree_dir/$default_slug-XXXXXX"); or return 1
        if not command git -C "$checkout" worktree add --detach "$worktree_path" "$base"
            command rmdir "$worktree_path" 2>/dev/null
            return 1
        end
        if not command herdr worktree open --workspace "$group" --path "$worktree_path" --focus
            printf 'Detached checkout remains at %s\n' "$worktree_path" >&2
            return 1
        end
    end
end
