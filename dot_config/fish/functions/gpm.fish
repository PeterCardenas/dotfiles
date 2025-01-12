function gpm
    set -l main_remote (git config --get branch.main.remote)
    set -l master_remote (git config --get branch.master.remote)
    if test -z "$main_remote" -a -z "$master_remote"
        print_error "Neither master nor main remotes are configured"
    end
    # Default to main remote if both are configured
    set -l default_branch
    set -l default_remote
    if test -n "$main_remote"
        set remote main
        set default_remote "$main_remote"
    else
        set remote master
        set default_remote "$master_remote"
    end
    set -l cmd "git fetch $default_remote $default_branch:$default_branch && git rebase $default_branch"
    echo $cmd | fish_indent --ansi
    eval $cmd
end
