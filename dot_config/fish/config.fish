function fish_greeting
    fortune
end

function fish_title
    echo (fish_prompt_pwd_dir_length=1 prompt_pwd);
end

source "$HOME"/.config/fish/colors.fish

set -gx GPG_TTY (tty)

# OS Specific
set -l os (uname -s)
if test $os = Linux
    abbr -a aptinst "sudo apt install"
    abbr -a aptupd "sudo apt update"
    abbr -a aptrm "sudo apt remove"

    # WSL
    if uname -a | grep -q WSL2
        set -gx BROWSER "/mnt/c/Program\ Files/Mozilla\ Firefox/firefox.exe"
    end
else if test $os = Darwin
    set -gx BROWSER /Applications/Firefox.app/Contents/MacOS/firefox
end

# Use .gitignore for fzf
set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden'

abbr -a cheznous "chezmoi git pull -- --rebase && chezmoi merge-all"

# Start Starship
source "$HOME"/.config/starship/config.fish
starship init fish | source
