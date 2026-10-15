function clone -d "Clones a repo" -a repo_name
    clone-common personal-github.com personal "$repo_name" $argv[2..-1]
end
