function clone -d "Clones a repo with ssh alias" -a alias_name -a repo_name
    set -l ssh_alias
    switch "$alias_name"
        case personal
            set ssh_alias personal-github.com
        case work
            set ssh_alias work-github.com
        case '*'
            print_error "Invalid alias name: $alias_name"
            return 1
    end
    git clone "$ssh_alias:$repo_name"
end
