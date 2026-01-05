function nvimpager -d "Open nvim as a pager" -a file
    if isatty stdin
        # No stdin pipe, use file argument
        if test -r "$file"
            nvim --cmd 'set eventignore=FileType' +'nnoremap q ZQ' +'call nvim_open_term(0, {})' +'set nomodified nolist' +'stopinsert' +'$' "$file"
        else
            echo "Usage: nvimpager <file> or pipe data to nvimpager" >&2
            return 1
        end
    else
        # Reading from stdin
        nvim --cmd 'set eventignore=FileType' +'nnoremap q ZQ' +'call nvim_open_term(0, {})' +'set nomodified nolist' +'stopinsert' +'$' -
    end
end
