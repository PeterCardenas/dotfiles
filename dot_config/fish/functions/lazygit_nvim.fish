function lazygit_nvim
    set -l file_or_dir
    set -l line
    for arg in $argv
        if test -f $arg; or test -d $arg
            set file_or_dir $file_or_dir $arg
        else
            set line $arg
        end
    end
    if test -z "$NVIM"
        if test -z "$line"
            nvim -- $file_or_dir
        else
            nvim +$line -- $file_or_dir
        end
        return
    end
    if test -z "$line"
        nvim --server "$NVIM" --remote-expr "execute(\"lua vim.cmd([[e $file_or_dir]])\")"
        return
    end
    nvim --server "$NVIM" --remote-expr "execute(\"lua vim.cmd([[e +$line $file_or_dir]])\")"
end
