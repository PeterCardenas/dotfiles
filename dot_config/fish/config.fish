if status is-interactive
  source $HOME/.config/fish/interactive_config.fish
end


if not set -q FAST_PROMPT
  # MUST BE AT END OF FILE
  # Start Starship
  starship init fish | source
end
