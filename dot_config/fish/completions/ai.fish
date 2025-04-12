# Remove files as completions.
complete -f -c ai

function __ai_session_names
    set sessions_dir "$HOME/.config/aichat/sessions"
    set session_names (ls --color=none -1 $sessions_dir | string replace --regex '\.yaml$' '')
    for session_name in $session_names
        set -l yaml_file "$sessions_dir/$session_name.yaml"
        if not test -d "$yaml_file"; and test -f "$yaml_file"
            echo -e "$session_name\tSession"
        end
    end
end

complete -f -c ai -n '__fish_is_arg_eq_nth 1' -a '(__ai_session_names)'
