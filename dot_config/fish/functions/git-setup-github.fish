function git-setup-github --description 'Set the gh default repo for the current clone, setting up an existing fork' -a owner repo
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
        set -l repo_name "$owner/$repo"
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
