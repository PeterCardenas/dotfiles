function sync_herdr_ssh_connection --description "Adopt the SSH origin of the Herdr client currently in use"
    if not set -q HERDR_ENV
        return
    end

    # Ask which client is being driven right now rather than trusting the value
    # this pane started with: the server outlives clients, and a local terminal
    # and an SSH attach can be connected at the same time.
    set -l connection (herdr-client-connection)
    if test -n "$connection"
        set -gx SSH_CONNECTION $connection
    else
        set -e SSH_CONNECTION
    end
end
