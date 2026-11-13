function herdr_error_message --description 'Extract the human-readable message from Herdr CLI error output' --argument-names output
    set -l message (printf '%s\n' "$output" | jq -er '.error.message | strings | select(length > 0)' 2>/dev/null)
    if test $status -eq 0
        printf '%s\n' $message
    else if not printf '%s\n' "$output" | jq -e . >/dev/null 2>&1
        printf '%s\n' "$output"
    else
        printf '%s\n' 'Herdr returned an error without a message.'
    end
end
