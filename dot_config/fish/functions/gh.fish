function gh
    if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l active_user (command gh api user --jq '.login' 2>/dev/null)
        if test $status -eq 0
            print_warn "Not in a git repository, using active user: $active_user"
        else
            print_warn "Not in a git repository"
        end
        command gh $argv
        return
    end
    set -l remote_url (git config --get remote.origin.url)
    set -l gh_user PeterCardenas
    if test -n "$(string match -e 'work-github.com' "$remote_url")"
        set gh_user peter-cardenas-ai
    else if test -z "$(string match -e 'personal-github.com' "$remote_url")"
        print_warn "GitHub user could not be determined from remote URL: $remote_url, using default user: $gh_user"
    end
    set -l gh_token (command gh auth token --user $gh_user)
    if test $status -ne 0
        print_error "Failed to get gh token for user $gh_user"
        return 1
    end
    print_info "Running for $gh_user"
    env GH_TOKEN=$gh_token gh $argv
end
