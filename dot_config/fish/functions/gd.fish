function gd
    set -l default_branch (gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
    set -l merge_base "$(git merge-base HEAD origin/$default_branch)"
    set -l numstat_cmd "git diff --numstat $merge_base"
    set -l shortstat_cmd "git diff --shortstat $merge_base"
    echo $numstat_cmd | fish_indent --ansi
    eval $numstat_cmd
    echo $shortstat_cmd | fish_indent --ansi
    eval $shortstat_cmd
end
