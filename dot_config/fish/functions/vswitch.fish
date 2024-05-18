# Switch neovim versions
function vswitch -d "Switch neovim configurations and sync versions" -a config_name
  # Pre-emptively errors before any destructive action.
  function print_error -a error_msg
    set_color red
    echo -n "[ERROR]"
    set_color normal
    echo ": $error_msg"
  end
  function print_warn -a warn_msg
    set_color yellow
    echo -n "[WARN]"
    set_color normal
    echo ": $warn_msg"
  end
  function print_info -a info_msg
    set_color green
    echo -n "[INFO]"
    set_color normal
    echo ": $info_msg"
  end
  set config_dir "$HOME/.config/nvim_conf/$config_name"
  if not test -d $config_dir
    print_error "Config directory does not exist for path $config_dir"
    return 1
  end
  set version_filename "$config_dir/nvim.version"
  if not test -e $version_filename
    print_error "Version file does not exist for config $config_name"
    return 1
  end
  set version_file_contents (cat $version_filename)
  if test (count $version_file_contents) -eq 0
    print_error "Version file does not contain any version"
    return 1
  end
  set requested_version $version_file_contents[1]
  if test (count $version_file_contents) -ne 1
    print_warn "Version file has an excessive amount of contents, using the first line as the version: $requested_version"
  end

  # Remove the existing link if it exists.
  print_info "Removing existing neovim configuration..."
  rm -rf $HOME/.config/nvim
  if test $status -ne 0
    print_warn "Existing neovim configuration did not exist."
  end
  # Link selected config to the natural neovim config location.
  print_info "Linking selected configuration..."
  ln -s $config_dir $HOME/.config/nvim
  if test $status -ne 0
    print_error "Failed to link configuration for $config_name."
    return 1
  end
  # Let bob install the right neovim version.
  print_info "Bob is syncing to version $requested_version..."
  bob sync
  if test $status -ne 0
    print_error "Bob failed to sync."
    return 1
  end
end
