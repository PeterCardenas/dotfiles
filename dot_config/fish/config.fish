function fish_greeting
    fortune
end

function fish_title
    echo (fish_prompt_pwd_dir_length=1 prompt_pwd);
end

# Exports
set -gx BROWSER /Applications/Firefox.app/Contents/MacOS/firefox
set -gx GPG_TTY (tty)

if test (uname -s) = Linux
    abbr -a aptinst "sudo apt install"
    abbr -a aptupd "sudo apt update"
    abbr -a aptrm "sudo apt remove"
end

# Use .gitignore for fzf
set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden'

# Start Starship
set -l starship_conf "$HOME"/.config/starship/config.fish
if test -f $starship_conf
    source $starship_conf
end
starship init fish | source
