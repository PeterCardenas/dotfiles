function gpl
    set -l cmd "git pull $(get_remote) $(git branch --show-current)"
    echo $cmd | fish_indent --ansi
    eval $cmd
end
