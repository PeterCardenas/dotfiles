function fix_display
  # If tmux is running, set DISPLAY to tmux's value.
  if set -q TMUX
    if not tmux showenv DISPLAY > /dev/null 2>&1
      if set -q DISPLAY
        set -e DISPLAY
      end
      return 0
    end
    set -l tmux_display (tmux showenv DISPLAY | cut -d= -f2)
    set -gx DISPLAY "$tmux_display"
  else if set -q DISPLAY; and string match -q -r "^:[0-9]\$" $DISPLAY
    set -gx DISPLAY "$(hostname)$DISPLAY"
  else if not set -q DISPLAY
    set -gx DISPLAY "$(hostname):0"
  end
end
