function clone-common --description 'Clone a repository (or import it into stol with --stol)' -a ssh_alias -a identity -a repo_name
    set -l repo_matches (string match -gr '(.*)/(.*)' $repo_name)
    if test (count $repo_matches) -ne 2
        print_error "Failed to parse repo name: $repo_name"
        return 1
    end
    set -l owner $repo_matches[1]
    set -l repo $repo_matches[2]
    set repo (string replace -r '\.git$' '' -- "$repo")
    set -l extra_args $argv[4..-1]
    if contains -- --stol $extra_args
        clone-into-stol "$ssh_alias" "$identity" "$owner" "$repo" (string match -v -- --stol $extra_args)
        return
    end
    # A second clone in ~/projects would split work across two layouts; stol owns repos it manages.
    if set -q STOL_ROOT; and test -d "$STOL_ROOT/projects/$repo/.repo"
        print_error "$repo is managed by stol at $STOL_ROOT/projects/$repo; use scd -e <branch> $repo or Herdr's linked-worktree popup in its group."
        return 1
    end
    mkdir "$repo"; or return 1
    git clone --bare "$ssh_alias:$repo_name" $argv[4..-1] "$repo/.bare"
    if test $status -ne 0
        print_error "Failed to clone $repo_name"
        return 1
    end
    printf 'gitdir: ./.bare\n' >"$repo/.git"; or return 1
    cd "$repo"
    if test $status -ne 0
        print_error "No repo at $repo"
        return 1
    end
    git-setup-clone "$identity"; or return 1
    # Bare clones omit remote-tracking refs; restore normal fetch and pull behavior.
    git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'; or return 1
    git fetch origin; or return 1
    set -l default_branch (git symbolic-ref --short HEAD); or return 1
    git worktree add "$default_branch" "$default_branch"; or return 1
    cd "$default_branch"; or return 1
    git branch --set-upstream-to="origin/$default_branch" "$default_branch"; or return 1
    git-setup-github "$owner" "$repo"
end

function clone-into-stol --description 'Import a repository into stol and give it the same setup as clone' -a ssh_alias identity owner repo
    if not set -q STOL_ROOT
        print_error "STOL_ROOT is not set; cannot import $owner/$repo into stol."
        return 1
    end
    stol import "$ssh_alias:$owner/$repo.git" --name "$repo" $argv[5..-1]; or return 1
    # Every stol worktree shares .repo's config, so identity and GitHub setup live there.
    cd "$STOL_ROOT/projects/$repo/.repo"; or return 1
    git-setup-clone "$identity"; or return 1
    git-setup-github "$owner" "$repo"; or return 1
    cd ..
end
