function herdr_popup_read --description 'Read a wrapped, cancellable Herdr popup prompt' -a message
    bind escape exit
    bind ctrl-c exit
    printf '%s\n' "$message" >&2
    # EOF is a cancel, not a failure, so herdr_popup_run closes without pausing.
    read --prompt-str '> ' response; or return 130
    printf '%s\n' "$response"
end
