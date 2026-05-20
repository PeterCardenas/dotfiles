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
        # Reading from stdin — stream via a tempfile + :terminal tail -f so
        # piping `tail -f` (or any unbounded producer) renders live instead of
        # blocking on EOF the way `nvim -` does.
        set tmpf (mktemp --suffix=.nvpager)
        cat >$tmpf &
        set writer $last_pid
        # eventignore=TermOpen suppresses the user's TermOpen autocmd that
        # calls `startinsert` — we want normal mode so `q` quits.
        # tnoremap q is a safety net if anything else flips us into terminal mode.
        nvim --cmd 'set eventignore=FileType,TermOpen' \
            +'nnoremap q ZQ' \
            +'tnoremap q <C-\><C-n>:qa!<CR>' \
            +'set nomodified nolist nonumber norelativenumber foldcolumn=0 statuscolumn=' \
            +"terminal tail -n +1 -f $tmpf" </dev/tty
        kill $writer 2>/dev/null
        rm -f $tmpf
    end
end
