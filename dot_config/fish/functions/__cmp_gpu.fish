function __cmp_gpu
    set -l cmd "git push -u origin $(git branch --show-current)"
    echo $cmd
end
