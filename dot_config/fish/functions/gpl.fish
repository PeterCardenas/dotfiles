function gpl
    set -l remote_name (git rev-parse --abbrev-ref --symbolic-full-name @{u} | sed 's/\/.*//')
    if test $pipestatus[1] -ne 0
        set -l remote_name origin
    end
    set -l current_branch (git branch --show-current)
    echo git pull $remote_name $current_branch
    git pull $remote_name $current_branch
end
