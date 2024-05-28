function gd
    echo git diff --numstat \(git merge-base HEAD origin/master\)
    echo git diff --shortstat \(git merge-base HEAD origin/master\)
    git diff --numstat (git merge-base HEAD origin/master)
    git diff --shortstat (git merge-base HEAD origin/master)
end
