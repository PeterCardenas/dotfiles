function print_warn -a warn_msg
    if not isatty stderr
        return
    end
    set_color yellow >&2
    echo -n "[WARN]" >&2
    set_color normal >&2
    echo ": $warn_msg" >&2
end
