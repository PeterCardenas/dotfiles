# Remove files as completions.
complete -f -c clone

complete -f -c clone -n '__fish_is_arg_eq_nth 1' -a 'personal work' -d 'ssh alias'
