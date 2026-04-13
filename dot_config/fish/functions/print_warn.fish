function print_warn -d "Print a warning message" -a warn_msg
    if isatty stderr
        set_color yellow >&2
    end
    echo -n "[WARN]" >&2
    if isatty stderr
        set_color normal >&2
    end
    echo ": $warn_msg" >&2
end
