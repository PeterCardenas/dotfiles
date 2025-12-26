function clone -d "Clones a repo" -a repo_name
    set ssh_alias personal-github.com
    set git_dir ".local/share/chezmoi"
    clone-common $ssh_alias $git_dir "$repo_name" $argv[2..-1]
end
