function copy_pr_link
    set github_link (gh pr view --json url --jq '.url')
    # Check if getting the PR link was successful
    if test $status -ne 0
        echo "Failed to get PR link"
        return 1
    end
    osc52_copy "$github_link"
    echo "Copied $github_link to clipboard"
end
