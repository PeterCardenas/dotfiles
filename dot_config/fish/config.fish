if status is-interactive
  source $HOME/.config/fish/interactive_config.fish
end

# Update PATH for both interactive and non-interactive shells
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
fish_add_path -P $PNPM_HOME\
 "$HOME/.local/share/bob/nvim-bin"\
 "$HOME/.local/bin"\
 "$HOME/go/bin"\
 "/usr/local/go/bin"\
 "$HOME/.cargo/bin"

set -l os (uname -s)
if test $os = Darwin
  fish_add_path -P "/Applications/WezTerm.app/Contents/MacOS"\
  "/Applications/kitty.app/Contents/MacOS"
end

set -U async_prompt_inherit_variables all

set -gx XDG_CONFIG_HOME $HOME/.config

export BAT_THEME="tokyonight_storm"

if not set -q FAST_PROMPT
  # MUST BE AT END OF FILE
  # Start Starship
  starship init fish | source
end
