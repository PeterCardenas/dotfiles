function clone-common --description 'Clone a repository' -a ssh_alias -a git_dir -a user -a repo_name
    set -l git_dir "$HOME/$git_dir/.git"
    set -l repo_matches (string match -gr '(.*)/(.*)' $repo_name)
    if test (count $repo_matches) -ne 2
        print_error "Failed to parse repo name: $repo_name"
        return 1
    end
    set -l owner $repo_matches[1]
    set -l repo $repo_matches[2]
    git clone "$ssh_alias:$repo_name" $argv[5..-1]
    if test $status -ne 0
        print_error "Failed to clone $repo_name"
        return 1
    end
    set repo_matches (string match -gr '(.*)\.git' $repo)
    if test (count $repo_matches) -eq 1
        set repo $repo_matches[1]
    end
    cd "$repo"
    if test $status -ne 0
        print_error "No repo at $repo"
        return 1
    end
    if test -d "$git_dir"
        set -l user_email (git --git-dir="$git_dir" config --get user.email)
        set -l signing_key (git --git-dir="$git_dir" config --get user.signingkey)
        git config --local user.email "$user_email"
        git config --local user.signingkey "$signing_key"
    else
        print_error "Known git dir not found: $git_dir"
        return 1
    end
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
    ' --jq ".data.repository.forks.nodes[]? | .owner.login + \"/\" + .name")
    if test $status -ne 0
        print_error "Failed to get forks for $repo"
        return 1
    end
    if test (count $existing_fork) -eq 1
        print_info "Setting up existing fork"
        setup_fork
    end
end
