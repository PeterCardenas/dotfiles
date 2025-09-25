function clone -d "Clones a repo" -a repo_name
    set ssh_alias personal-github.com
    set git_dir ".local/share/chezmoi"
    set user PeterCardenas
    clone-common $ssh_alias $git_dir $user "$repo_name" $argv[2..-1]
end
