function fix_display
  # If tmux is running, set DISPLAY to tmux's value.
  if test -n "$TMUX"
    set -l tmux_display (tmux show-environment DISPLAY | cut -d= -f2)
    set -gx DISPLAY "$tmux_display"
  else
    # Otherwise, set DISPLAY to hostname's value.
    set -gx DISPLAY "$(hostname)$DISPLAY"
  end
end
