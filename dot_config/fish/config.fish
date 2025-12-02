if status is-interactive
    source $HOME/.config/fish/interactive_config.fish
end

set -l os (uname -s)
if test $os = Darwin
    fish_add_path -P -m "/Applications/WezTerm.app/Contents/MacOS" \
        "/Applications/kitty.app/Contents/MacOS" \
        /opt/local/bin \
        /opt/local/sbin \
        /usr/local/bin \
        /opt/homebrew/bin \
        "$HOME/Library/Python/3.12/bin"

    set -l path_parts (string split ":" $DYLD_FALLBACK_LIBRARY_PATH)
    if test (count $path_parts) -eq 0
        set -gx DYLD_FALLBACK_LIBRARY_PATH /opt/local/lib
    else if not contains /opt/local/lib $path_parts
        set -gx DYLD_FALLBACK_LIBRARY_PATH /opt/local/lib:$DYLD_FALLBACK_LIBRARY_PATH
    end

    if set -q TERMINFO_DIRS
        set -gx TERMINFO_DIRS /opt/local/share/terminfo:$TERMINFO_DIRS
    else
        set -gx TERMINFO_DIRS /opt/local/share/terminfo
    end
    if set -q TERMINFO
        set -gx TERMINFO_DIRS $TERMINFO:$TERMINFO_DIRS
    end

    # Added by OrbStack: command-line tools and integration
    source ~/.orbstack/shell/init2.fish 2>/dev/null || :
else
    fish_add_path -P -m "$HOME/.local/kitty.app/bin" \
        /snap/bin
end

# Update PATH for both interactive and non-interactive shells
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
set -gx ZVM_INSTALL "$HOME/.zvm/self"
fish_add_path -P -m "$HOME/.local/share/bob/nvim-bin" \
    "$HOME/.local/bin" \
    "$HOME/go/bin" \
    /usr/local/go/bin \
    "$HOME/.cargo/bin" \
    "$HOME/.fish-lsp/bin" \
    "$PNPM_HOME" \
    "$HOME/.zvm/bin" \
    "$ZVM_INSTALL/" \
    # TODO: Remove when following issue is resolved: https://github.com/sst/opencode/issues/3097
    "$HOME/.opencode/bin"

if command -q ghostty
    set -gx GHOSTTY_BIN_DIR (dirname (which ghostty))
else
    echo "ghostty command not found"
end

set -g STARSHIP_CMD_PIPESTATUS
set -g STARSHIP_CMD_STATUS
set -g STARSHIP_DURATION
set -g STARSHIP_JOBS

function __prompt -a prompt_name
    set -l prompt_file $HOME/.config/starship_$prompt_name.toml
    switch "$fish_key_bindings"
        case fish_hybrid_key_bindings fish_vi_key_bindings
            set STARSHIP_KEYMAP "$fish_bind_mode"
        case '*'
            set STARSHIP_KEYMAP insert
    end
    env STARSHIP_CONFIG=$prompt_file starship prompt --status=$STARSHIP_CMD_STATUS --pipestatus="$STARSHIP_CMD_PIPESTATUS" --keymap=$STARSHIP_KEYMAP --cmd-duration=$STARSHIP_DURATION --jobs=$STARSHIP_JOBS
end
set -g prev_dir
set -g prev_git_dir
function __git_status_prompt
    __prompt git_status
end
function __git_status_prompt_loading_indicator -a last_prompt
    # TODO: fix bug where this is sometimes "."
    set -l current_dir (pwd)
    if test "$last_prompt" = "[J"
        set last_prompt "… "
    end
    if test "$current_dir" = "$prev_dir"
        echo -n $last_prompt
        return
    end
    set -l current_git_dir current_dir
    # check if the current directory is a git repository by traversing parent directories until $HOME or .git is found
    while test "$current_git_dir" != "$HOME" -a "$current_git_dir" != "$HOME/.git" -a "$current_git_dir" != "."
        if test -d $current_git_dir/.git
            if test "$current_git_dir" != "$prev_git_dir"
                echo -n "… "
            else
                echo -n $last_prompt
            end
            set prev_dir $current_dir
            set prev_git_dir $current_git_dir
            return
        end
        set current_git_dir (dirname $current_git_dir)
    end
    set prev_dir $current_dir
    set prev_git_dir
end
set -g async_prompt_inherit_variables all
set -g async_prompt_functions __git_status_prompt

set -gx XDG_CONFIG_HOME $HOME/.config

export BAT_THEME="tokyonight_storm"

if not set -q FAST_PROMPT
    function _prompt_post_exec --on-event fish_postexec
        set STARSHIP_CMD_PIPESTATUS $pipestatus
        set STARSHIP_CMD_STATUS $status
        set STARSHIP_DURATION "$CMD_DURATION"
        set STARSHIP_JOBS (count (jobs -p))
    end
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
