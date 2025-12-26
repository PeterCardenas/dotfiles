function setup_fork -d "Sets up a fork with ssh alias and sets default repo"
    if test -n "$(git config --get remote.upstream.url)"; and test -n "$(git config --get remote.origin.url)"
        print_error "Fork already set up"
        return 1
    end
    set -l upstream_url (git config --get remote.origin.url)
    if test -z "$upstream_url"
        print_error "Failed to get fork url for remote origin: $upstream_url"
        return 1
    end
    set -l fork_matches (string match -gr '(.*github.com):(.*)' $upstream_url)
    if test (count $fork_matches) -ne 2
        print_error "Failed to parse fork url: $upstream_url"
        return 1
    end
    set -l ssh_alias $fork_matches[1]
    set -l upstream_repo $fork_matches[2]
    set repo_matches (string match -gr '(.*)\.git' $upstream_repo)
    if test (count $repo_matches) -eq 1
        set upstream_repo $repo_matches[1]
    end
    gh repo set-default $upstream_repo
    gh repo fork --clone --remote
    if test $status -ne 0
        print_error "Failed to fork"
        return 1
    end
    set -l origin_url (git config --get remote.origin.url)
    if test -z "$origin_url"
        print_error "Failed to get remote url(s). upstream url: $upstream_url, origin url: $origin_url"
        return 1
    end
    set -l origin_matches (string match -gr 'git@github.com:(.*)' $origin_url)
    if test (count $origin_matches) -ne 1
        print_error "Failed to parse origin url: $origin_url"
        return 1
    end
    set -l origin_repo $origin_matches[1]
    git remote set-url origin "$ssh_alias:$origin_repo"
end
