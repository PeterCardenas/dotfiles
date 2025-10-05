function __fish_is_arg_eq_nth
    set tokens (commandline -xpc)
    set token_str (string replace -ra '(^|\-).+?\s+' '' -- $tokens)
    set token_str (string replace -ra '\s+' ' ' -- $token_str)
    set tokens (string split " " "$token_str")
    if test (count $tokens) -eq $argv[1]
        return 0
    end
    return 1
end

function __fish_needs_command -a command
    set tokens (commandline -xpc)
    if test (count $tokens) -eq 1; and test $tokens[1] = $command
        return 0
    end
    return 1
end

function __fish_is_token_ge_nth
    set tokens (commandline -xpc)
    if test (count $tokens) -ge $argv[1]
        return 0
    end
    return 1
end
