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
    # Resolve relative to LazyGit's cwd, which may differ from Neovim's cwd.
    set -l filename (path resolve -- "$file_or_dir")
    set -l quoted_filename (string replace -a "'" "''" -- "$filename")
    set -l edit_command edit
    if test -n "$line"
        string match -qr '^[0-9]+$' -- "$line"; or return 1
        set edit_command "edit +$line"
    end
    # fnameescape prevents Ex from expanding filename characters such as # and %.
    nvim --headless --server "$NVIM" --remote-expr "execute('$edit_command ' . fnameescape('$quoted_filename'))"
end
