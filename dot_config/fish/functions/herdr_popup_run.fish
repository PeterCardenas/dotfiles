function herdr_popup_run --description 'Run a Herdr popup command and keep its failure output visible'
    $argv
    set -l command_status $status
    # Herdr closes a popup as soon as its command exits; 130 marks a user cancel, which needs no pause.
    if test $command_status -ne 0; and test $command_status -ne 130
        set_color red >&2
        printf '%s failed (exit %s).\n' "$argv[1]" $command_status >&2
        set_color normal >&2
        herdr_popup_read 'Press Enter to close.' >/dev/null
    end
    return $command_status
end
