function print_error -d "Print an error message" -a error_msg
    if isatty stderr
        set_color red >&2
    end
    echo -n "[ERROR]" >&2
    if isatty stderr
        set_color normal >&2
    end
    echo ": $error_msg" >&2
end
