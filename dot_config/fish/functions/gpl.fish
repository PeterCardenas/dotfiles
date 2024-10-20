function gpl
    set -l cmd "git pull $(get_remote) $(git branch --show-current)"
    echo $cmd
    eval $cmd
end
