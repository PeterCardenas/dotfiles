function herdr_popup_read --description 'Read a wrapped, cancellable Herdr popup prompt' -a message
    bind escape exit
    bind ctrl-c exit
    printf '%s\n' "$message" >&2
    read --prompt-str '> ' response; or return 1
    printf '%s\n' "$response"
end
