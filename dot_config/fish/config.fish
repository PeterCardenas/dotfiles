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
        /opt/local/sbin \
        /usr/local/bin
    if set -q DYLD_FALLBACK_LIBRARY_PATH
        set -gx DYLD_FALLBACK_LIBRARY_PATH /opt/local/lib:$DYLD_FALLBACK_LIBRARY_PATH
    else
        set -gx DYLD_FALLBACK_LIBRARY_PATH /opt/local/lib
    end
else
    fish_add_path -P "$HOME/.local/kitty.app/bin"
end

function __prompt -a prompt_name
    set -l prompt_file $HOME/.config/starship_$prompt_name.toml
    echo $prompt_file >/tmp/prompt_file
    switch "$fish_key_bindings"
        case fish_hybrid_key_bindings fish_vi_key_bindings
            set STARSHIP_KEYMAP "$fish_bind_mode"
        case '*'
            set STARSHIP_KEYMAP insert
    end
    set STARSHIP_CMD_PIPESTATUS $pipestatus
    set STARSHIP_CMD_STATUS $status
    set STARSHIP_DURATION "$CMD_DURATION"
    set STARSHIP_JOBS (count (jobs -p))
    env STARSHIP_CONFIG=$prompt_file starship prompt --status=$STARSHIP_CMD_STATUS --pipestatus="$STARSHIP_CMD_PIPESTATUS" --keymap=$STARSHIP_KEYMAP --cmd-duration=$STARSHIP_DURATION --jobs=$STARSHIP_JOBS
end
function __git_status_prompt
    __prompt git_status
end
set -g async_prompt_inherit_variables all
set -g async_prompt_functions __git_status_prompt

set -gx XDG_CONFIG_HOME $HOME/.config

export BAT_THEME="tokyonight_storm"

if not set -q FAST_PROMPT
    # MUST BE AT END OF FILE
    function fish_prompt
        __prompt before_git_status
        __git_status_prompt
        __prompt after_git_status
    end

    # Disable virtualenv prompt, it breaks starship
    set -g VIRTUAL_ENV_DISABLE_PROMPT 1

    # Remove default mode prompt
    builtin functions -e fish_mode_prompt

    set -gx STARSHIP_SHELL fish

    # Set up the session key that will be used to store logs
    # We don't use `random [min] [max]` because it is unavailable in older versions of fish shell
    set -gx STARSHIP_SESSION_KEY (string sub -s1 -l16 (random)(random)(random)(random)(random)0000000000000000)
end
