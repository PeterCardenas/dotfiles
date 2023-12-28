function copy_pr_link
    set github_link (gh pr view --json url --jq '.url')
    echo $github_link | xclip -selection clipboard
    echo "Copied $github_link to clipboard"
end
