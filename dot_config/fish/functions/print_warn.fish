function print_warn -a warn_msg
    if status is-command-substitution
        return
    end
    set_color yellow
    echo -n "[WARN]"
    set_color normal
    echo ": $warn_msg"
end
