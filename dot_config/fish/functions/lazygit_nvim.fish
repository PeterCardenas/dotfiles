function lazygit_nvim -a file_or_dir -a line
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
