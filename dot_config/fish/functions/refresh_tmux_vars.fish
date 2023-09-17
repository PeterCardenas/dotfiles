# Add tmux variables to fish shell before a command is executed.
function refresh_tmux_vars --on-event fish_preexec
  if set -q TMUX
    tmux showenv | string replace -rf '^((?:SSH|DISPLAY|XAUTHORITY).*?)=(.*?)$' 'set -gx $1 "$2"' | source
  end
end
