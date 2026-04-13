function print_info -a info_msg
    if not isatty stderr
        return
    end
    set_color green >&2
    echo -n "[INFO]" >&2
    set_color normal >&2
    echo ": $info_msg" >&2
end
