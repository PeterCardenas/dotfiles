function print_error -a error_msg
    if status is-command-substitution
        return
    end
    set_color red
    echo -n "[ERROR]"
    set_color normal
    echo ": $error_msg"
end
