function __cmp_gcnm --description "Create a new branch of the default branch"
    set -l main_remote (git config --get branch.main.remote)
    set -l master_remote (git config --get branch.master.remote)
    if test -z "$main_remote" -a -z "$master_remote"
        return
    end
    # Default to main remote if both are configured
    set -l default_branch
    set -l default_remote
    if test -n "$main_remote"
        set default_branch main
        set default_remote "$main_remote"
    else
        set default_branch master
        set default_remote "$master_remote"
    end
    set -l cmd "git checkout -b % $default_branch"
    echo $cmd
end
