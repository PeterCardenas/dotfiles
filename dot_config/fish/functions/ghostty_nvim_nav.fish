function ghostty_nvim_nav -a directions --description "Set ghostty navigation keymaps for specified directions only"
    if not test "$TERM" = xterm-ghostty; or set -q TMUX; or set -q SSH_CONNECTION
        return 1
    end
    set -l ghostty_config_dir $HOME/.config/ghostty
    set -l lock_dir /tmp/ghostty_nvim_nav.lock
    set -l exit_code 0
    set -l max_retries 50
    set -l retry_delay 0.1

    # Acquire lock with retry logic using mkdir (atomic operation)
    set -l lock_acquired 0
    for i in (seq 1 $max_retries)
        if test -d $lock_dir
            # Check if lock is stale (PID file inside lock dir)
            set -l lock_pid (cat $lock_dir/pid 2>/dev/null)
            if test -n "$lock_pid"
                if not ps -p $lock_pid >/dev/null 2>&1
                    # Stale lock, remove it
                    rm -rf $lock_dir
                end
            end
        end

        # Try to acquire lock atomically with mkdir
        if mkdir $lock_dir 2>/dev/null
            echo $fish_pid >$lock_dir/pid
            set lock_acquired 1
            break
        end

        # Wait before retry
        sleep $retry_delay
    end

    if test $lock_acquired -eq 0
        print_error "Failed to acquire lock after $max_retries attempts"
        return 1
    end

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
        else
            sleep 0.1
        end
    end

    # Release lock
    rm -rf $lock_dir

    return $exit_code
end
