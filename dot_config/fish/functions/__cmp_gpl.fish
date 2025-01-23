function __cmp_gpl
    set -l current_branch "$(git branch --show-current)"
    set -l remote "$(git config --get branch.$current_branch.remote)"
    if test -z "$remote"
        return
    end
    set -l cmd "git pull $remote $current_branch"
    echo $cmd
end
