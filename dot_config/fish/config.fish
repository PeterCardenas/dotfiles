if status is-interactive
    source $HOME/.config/fish/interactive_config.fish
end

# Update PATH for both interactive and non-interactive shells
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
set -gx ZVM_INSTALL "$HOME/.zvm/self"
fish_add_path -P $PNPM_HOME \
    "$HOME/.local/share/bob/nvim-bin" \
    "$HOME/.local/bin" \
    "$HOME/go/bin" \
    /usr/local/go/bin \
    "$HOME/.cargo/bin" \
    "$HOME/.fish-lsp/bin" \
    "$HOME/.zvm/bin" \
    "$ZVM_INSTALL/"

set -l os (uname -s)
if test $os = Darwin
    fish_add_path -P "/Applications/WezTerm.app/Contents/MacOS" \
        "/Applications/kitty.app/Contents/MacOS" \
        /opt/local/bin \
        /opt/local/sbin
    # TODO: How to optionally add this only for image.nvim
    if set -q DYLD_LIBRARY_PATH
        set -gx DYLD_LIBRARY_PATH /opt/local/lib:$DYLD_LIBRARY_PATH
    else
        set -gx DYLD_LIBRARY_PATH /opt/local/lib
    end
else
    fish_add_path -P "$HOME/.local/kitty.app/bin"
end

set -g async_prompt_inherit_variables all

set -gx XDG_CONFIG_HOME $HOME/.config

export BAT_THEME="tokyonight_storm"

if not set -q FAST_PROMPT
    # MUST BE AT END OF FILE
    # Start Starship
    starship init fish | source
end
