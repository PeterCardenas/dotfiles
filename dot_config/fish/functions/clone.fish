function clone -d "Clones a repo with ssh alias" -a alias_name -a repo_name
    set -l ssh_alias personal-github.com
    set -l git_dir ".local/share/chezmoi"
    set -l git_dir "$HOME/$git_dir/.git"
    set -l repo_matches (string match -gr '.*/(.*)' $repo_name)
    if test (count $repo_matches) -ne 1
        print_error "Failed to parse repo name: $repo_name"
        return 1
    end
    set -l repo $repo_matches[1]
    git clone "$ssh_alias:$repo_name"
    if test -d "$git_dir"
        set -l user_email (git --git-dir="$git_dir" config --get user.email)
        set -l signing_key (git --git-dir="$git_dir" config --get user.signingkey)
        git --git-dir="$repo/.git" config --local user.email "$user_email"
        git --git-dir="$repo/.git" config --local user.signingkey "$signing_key"
    else
        print_error "Known git dir for alias $alias_name not found: $git_dir"
    end
end
