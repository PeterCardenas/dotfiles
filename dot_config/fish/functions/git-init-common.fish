function git-init-common --description 'Initialize a git repository' -a user -a git_dir -a ssh_alias -a repo_name
    if test -z "$repo_name"
        if test -d .git
            set repo_name (basename (pwd))
        else
            print_error "No repo name provided"
            return 1
        end
    else
        if string match -q '*/*' $repo_name
            print_error "Invalid repo name, cannot contain slashes: $repo_name"
            return 1
        end
        mkdir $repo_name
        cd $repo_name
        git init
    end
    git remote add origin "$ssh_alias:$user/$repo_name.git"
    if test -d "$git_dir"
        set -l user_email (git --git-dir="$git_dir" config --get user.email)
        set -l signing_key (git --git-dir="$git_dir" config --get user.signingkey)
        git config --local user.email "$user_email"
        git config --local user.signingkey "$signing_key"
    else
        print_error "Known git dir not found: $git_dir"
        return 1
    end
end
