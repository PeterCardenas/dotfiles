function print_info -a info_msg
    if status is-command-substitution; or not isatty stdout
        return
    end
    set_color green
    echo -n "[INFO]"
    set_color normal
    echo ": $info_msg"
end
