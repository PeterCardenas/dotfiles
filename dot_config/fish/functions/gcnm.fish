function gcnm --description "Create a new branch of the default branch"
    set -l default_branch (git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    set -l cmd "git checkout -b $argv $default_branch"
    echo $cmd | fish_indent --ansi
    eval $cmd
end
