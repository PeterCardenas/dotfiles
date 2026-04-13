function print_error -d "Print an error message" -a error_msg
    if not isatty stderr
        return
    end
    set_color red >&2
    echo -n "[ERROR]" >&2
    set_color normal >&2
    echo ": $error_msg" >&2
end
