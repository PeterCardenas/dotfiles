function gpu
    set -l cmd "git push -u origin $(git branch --show-current)"
    echo $cmd | fish_indent --ansi
    eval $cmd
end
