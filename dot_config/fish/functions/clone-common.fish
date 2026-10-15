function clone-common --description 'Clone a repository' -a ssh_alias -a identity -a repo_name
    set -l repo_matches (string match -gr '(.*)/(.*)' $repo_name)
    if test (count $repo_matches) -ne 2
        print_error "Failed to parse repo name: $repo_name"
        return 1
    end
    set -l owner $repo_matches[1]
    set -l repo $repo_matches[2]
    set repo (string replace -r '\.git$' '' -- "$repo")
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
    git-config-identity "$identity"; or return 1
    git config --local user.name "Peter Cardenas"; or return 1
    # Bare clones omit remote-tracking refs; restore normal fetch and pull behavior.
    git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'; or return 1
    git fetch origin; or return 1
    set -l default_branch (git symbolic-ref --short HEAD); or return 1
    git worktree add "$default_branch" "$default_branch"; or return 1
    cd "$default_branch"; or return 1
    git branch --set-upstream-to="origin/$default_branch" "$default_branch"; or return 1
    set -l existing_fork (gh api graphql -F owner="$owner" -F name="$repo" -f query='
query GetUserForksForRepo($owner: String!, $name: String!) {
  repository(name: $name, owner: $owner) {
    forks(first: 1, affiliations: [OWNER]) {
      nodes {
        name
        owner {
          login
        }
      }
    }
  }
}
    ' --jq '.data.repository.forks.nodes[]? | .owner.login + "/" + .name')
    if test $status -ne 0
        print_error "Failed to get forks for $repo"
        return 1
    end
    set -l gh_user (gh api user --jq '.login')
    if test $status -ne 0; or test -z "$gh_user"
        print_error "Failed to detect GitHub user"
        return 1
    end
    set -l is_user_owned 0
    if string match -q -- "$gh_user" "$owner"
        set is_user_owned 1
    end
    if test (count $existing_fork) -eq 1
        print_info "Setting up existing fork"
        setup_fork
    else
        set repo_matches (string match -gr '(.*)\.git' $repo_name)
        if test (count $repo_matches) -eq 1
            set repo_name $repo_matches[1]
        end
        if test $is_user_owned -eq 1
            gh repo set-default $repo_name
            return $status
        end
        if status is-interactive; and isatty stdin
            read --local --prompt-str "No existing fork found for $repo_name. Set one up now? [y/N] " should_setup_fork
            if string match -rqi '^(y|yes)$' -- "$should_setup_fork"
                setup_fork
                return $status
            end
        end
        gh repo set-default $repo_name
    end
end
