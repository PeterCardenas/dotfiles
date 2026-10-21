function bob --wraps bob
    set -l token (gh auth token); or return $status
    env GITHUB_TOKEN="$token" bob $argv
end
