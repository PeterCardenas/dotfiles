if status is-interactive
  source $HOME/.config/fish/interactive_config.fish
end

set -gx PNPM_HOME "$HOME/.local/share/pnpm"
set BOB_NVIM_BIN "$HOME/.local/share/bob/nvim-bin"
set LOCAL_BIN "$HOME/.local/bin"
fish_add_path -P $PNPM_HOME $BOB_NVIM_BIN $LOCAL_BIN

if not set -q FAST_PROMPT
  # MUST BE AT END OF FILE
  # Start Starship
  starship init fish | source
end
