function get_remote
    set -l remote_name (git rev-parse --abbrev-ref --symbolic-full-name @{u} | sed 's/\/.*//')
    if test $pipestatus[1] -ne 0
        set remote_name origin
    end
    echo $remote_name
end
