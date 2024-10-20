function gpu
    set -l remote_name (get_remote)
    set -l cmd "git push -u $remote_name $(git branch --show-current)"
    echo $cmd
    eval $cmd
end
