function ai -a session_name
    set -l prompt $argv[2..-1]
    aichat --prompt "Keep responses short. Avoid making long lists and if there are multiple options only output at most 3 with very short descriptions" --save-session --session $session_name $prompt
end
