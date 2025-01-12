function gpl
    set -l current_branch "$(git branch --show-current)"
    set -l remote "$(git config --get branch.$current_branch.remote)"
    if test -z "$remote"
        print_error "No remote configured for $current_branch"
    end
    set -l cmd "git pull $remote $current_branch"
    echo $cmd | fish_indent --ansi
    eval $cmd
end
