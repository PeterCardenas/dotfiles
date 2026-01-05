function ghostty_nvim_nav -a directions --description "Set ghostty navigation keymaps for specified directions only"
    set -l ghostty_config_dir $HOME/.config/ghostty
    set -l exit_code 0

    # All possible directions
    set -l all_directions h j k l

    # Parse directions (empty means disable all)
    set -l enabled_dirs
    if test -n "$directions"
        if test "$directions" = all
            set enabled_dirs $all_directions
        else
            # Convert comma-separated string to array
            set enabled_dirs (string split "," $directions)
        end
    end

    # First, disable all directions
    for dir in $all_directions
        set -l active_keymap $ghostty_config_dir/active_nvim_keymaps_$dir
        if test -f $active_keymap
            rm $active_keymap
        end
    end

    # Then, enable only the specified directions
    for dir in $enabled_dirs
        set -l source_keymap $ghostty_config_dir/nvim_keymaps_$dir
        set -l active_keymap $ghostty_config_dir/active_nvim_keymaps_$dir

        if test -f $source_keymap
            cp $source_keymap $active_keymap
        else
            print_error "Source keymap file not found: $source_keymap"
            set exit_code 1
        end
    end

    # Reload ghostty config
    if test $exit_code -eq 0
        reload_ghostty_config
        if test $status -ne 0
            print_error "Failed to reload ghostty config"
            set exit_code 1
        end
    end

    return $exit_code
end
