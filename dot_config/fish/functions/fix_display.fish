function fix_display
  # If tmux is running, set DISPLAY to tmux's value.
  if set -q TMUX
    set -l tmux_display (tmux show-environment DISPLAY | cut -d= -f2)
    set -gx DISPLAY "$tmux_display"
  else if set -q DISPLAY; and string match -q -r "^:[0-9]\$" $DISPLAY
    set -gx DISPLAY "$(hostname)$DISPLAY"
  else if not set -q DISPLAY
    set -gx DISPLAY "$(hostname):0"
  end
end
