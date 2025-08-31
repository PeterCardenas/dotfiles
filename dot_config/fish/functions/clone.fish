function clone -d "Clones a repo with ssh alias" -a alias_name -a repo_name
    set ssh_alias personal-github.com
    set git_dir ".local/share/chezmoi"
    set user PeterCardenas
    clone-common $ssh_alias $git_dir $user "$alias_name" "$repo_name"
end
