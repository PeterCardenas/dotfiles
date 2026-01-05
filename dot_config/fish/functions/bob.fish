function bob --wraps bob
    set -l token (command gh auth token)
    env GITHUB_TOKEN="$token" bob $argv
end
