function print_info -d "Print an info message" -a info_msg
    if isatty stderr
        set_color green >&2
    end
    echo -n "[INFO]" >&2
    if isatty stderr
        set_color normal >&2
    end
    echo ": $info_msg" >&2
end
