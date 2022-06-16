function fish_greeting
	fortune
end

# Exports
set -gx BROWSER /Applications/Firefox.app/Contents/MacOS/firefox
set -gx GPG_TTY (tty)

# Use .gitignore for fzf
set -gx FZF_DEFAULT_COMMAND "fd --type f"
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND

# Start Starship
set -l starship_conf "$HOME"/.config/starship/config.fish
if test -f $starship_conf
    source $starship_conf
end
starship init fish | source
