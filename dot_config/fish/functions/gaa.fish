function gaa
    echo git add (git rev-parse --show-toplevel) | fish_indent --ansi
    git add (git rev-parse --show-toplevel)
end
