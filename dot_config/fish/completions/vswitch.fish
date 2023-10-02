# Removes files as completions.
complete -f -c vswitch -n '__fish_needs_command vswitch'

function __vswitch_config_names
  set configs_dir "$HOME/.config/nvim_conf"
  set config_names (ls --color=none -1 $configs_dir | string trim --right --chars '/')
  for config_name in $config_names
    echo -e "$config_name\tNeovim Configuration Directory"
  end
end
# First token is the config name.
complete -f -c vswitch -n '__fish_needs_command vswitch' -a "(__vswitch_config_names)"
