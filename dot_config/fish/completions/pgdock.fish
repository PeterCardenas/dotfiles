function __pgdock_get_database_names
    set root_dir (__get_app_root)
    # TODO: Handle when the container is not running in a performant way.
    # Remove the greeting message first line and the empty last line.
    $root_dir/dev/containers/dev/into_pg.sh -c "psql -U dev_user -d postgres -P pager=off -t -c 'SELECT datname FROM pg_database WHERE datistemplate = false;'" | sed '$d' | sed 1d | string trim
end

# Removes files as completions.
complete -f -c pgdock -n '__fish_needs_command pgdock'

# First token is the database names.
complete -f -c pgdock -n '__fish_needs_command pgdock' -a "(__pgdock_get_database_names)"
