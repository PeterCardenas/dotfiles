function grs
    echo git restore -s $argv[1] -SW -- $argv[2..-1] | fish_indent --ansi
    git restore -s $argv[1] -SW -- $argv[2..-1]
end
