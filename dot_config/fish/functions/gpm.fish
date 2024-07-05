function gpm
    set -l default_branch (git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    set -l cmd "git fetch origin $default_branch:$default_branch && git rebase $default_branch"
    echo $cmd
    eval $cmd
end
