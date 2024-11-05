function gr
    echo git restore (git rev-parse --show-toplevel) | fish_indent --ansi
    git restore (git rev-parse --show-toplevel)
end
