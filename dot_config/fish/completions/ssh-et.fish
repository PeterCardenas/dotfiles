# Copies the completions from ssh to ssh-et.
# Not all commands are supported, but this is the lowest lift work.
# Reference: https://github.com/infokiller/ssh-et
complete -c ssh-et -a '(__fish_use_subcommand)' -n '__fish_seen_subcommand_from ssh'
