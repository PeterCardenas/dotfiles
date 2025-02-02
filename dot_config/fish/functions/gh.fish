function gh
    set -l remote_url (git config --get remote.origin.url)
    if test -z "$remote_url"
        print_error "Cannot determine current user with remote: $remote_url"
        return 1
    end
    set -l gh_user PeterCardenas
    if test -n "$(string match -e 'work-github.com' "$remote_url")"
        set gh_user peter-cardenas-ai
    end
    set -l gh_token (command gh auth token --user $gh_user)
    if test $status -ne 0
        print_error "Failed to get gh token for user $gh_user"
        return 1
    end
    if not status is-command-substitution
        print_info "Running for $gh_user"
    end
    env GH_TOKEN=$gh_token gh $argv
end
