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

set -U async_prompt_inherit_variables all

if not set -q FAST_PROMPT
  # MUST BE AT END OF FILE
  # Start Starship
  starship init fish | source
end
