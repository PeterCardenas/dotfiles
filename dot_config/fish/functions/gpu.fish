function gpu
    set -l cmd "git push -u origin $(git branch --show-current)"
    echo $cmd
    eval $cmd
end
