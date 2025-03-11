function __cmp_gpl
    set -l current_branch "$(git branch --show-current)"
    set -l remote "$(git config --get branch.$current_branch.remote)"
    # TODO: Sometimes remote is not set, so we should check where the ref is.
    # For now default to origin.
    if test -z "$remote"
        set remote origin
    end
    set -l cmd "git pull $remote $current_branch"
    echo $cmd
end
