function herdr_new_session --description 'Clone a repo and focus its checkout in a new Herdr worktree group' -a repo
    command mkdir -p "$HOME/projects"; or return 1
    cd "$HOME/projects"; or return 1
    # Run in this shell, not a substitution, so clone output streams into the popup.
    clone "$repo"; or return $status
    set -l checkout "$PWD"
    set -l common_dir (command git rev-parse --path-format=absolute --git-common-dir); or return 1
    set -l is_bare (command git --git-dir="$common_dir" rev-parse --is-bare-repository); or return 1
    if test "$is_bare" != true
        printf '%s\n' 'Expected clone to create a bare repository; no workspace was created.' >&2
        return 1
    end
    set -l container (path dirname "$common_dir")
    # The bare container is the group parent; opening the checkout links it as a child.
    set -l created (command herdr workspace create --cwd "$container" --label (path basename "$container") --no-focus); or return 1
    set -l workspace (printf '%s\n' "$created" | jq -r '.result.workspace.workspace_id // empty'); or return 1
    test -n "$workspace"; or return 1
    if not command herdr worktree open --workspace "$workspace" --path "$checkout" --focus
        printf 'Checkout remains at %s; repository workspace is %s.\n' "$checkout" "$workspace" >&2
        return 1
    end
end
