function fish_greeting
    # Only print fortune if it exists.
    if command -q fortune
    else
        return 0
    end
    # Print empty line for some top "padding"
    echo
    set_color yellow
    fortune
    set_color normal
end

# Clear all previous abbreviations
abbr -e (abbr -l)

# Enable vim keybindings
set -g fish_key_bindings fish_vi_key_bindings
# Bar cursor for insert mode
set -g fish_cursor_insert line
# Block cursor for normal and visual mode
set -g fish_cursor_default block
# Underline cursor for replace mode
set -g fish_cursor_replace_one underscore
set -g fish_cursor_replace underscore
# Force cursor for tmux (since it is supported).
set -g fish_vi_force_cursor 1

# Allow mouse for less
set -gx LESS "--mouse --wheel-lines=3"

source $HOME/.config/fish/colors.fish
source $HOME/.config/fish/completion_utils.fish

# Set the SSH_AUTH_SOCK variable.
if not set -q SSH_AUTH_SOCK
    eval (ssh-agent -c) >/dev/null
end

# Add ghostty completions
set -l GHOSTTY_COMPLETION_PATH /Applications/Ghostty.app/Contents/Resources/fish/vendor_completions.d/ghostty.fish
if test -e $GHOSTTY_COMPLETION_PATH
    rm -f $HOME/.config/fish/completions/ghostty.fish
    ln -s $GHOSTTY_COMPLETION_PATH $HOME/.config/fish/completions/ghostty.fish
end

# Add tmux variables to fish shell before a command is executed.
function refresh_tmux_vars --on-event fish_preexec
    if set -q TMUX
        set -e XAUTHORITY
        set -e SSH_CONNECTION
        set -e SSH_TTY
        set -e SSH_AUTH_SOCK
        tmux showenv | string replace -rf '^((?:DISPLAY|SSH_CONNECTION|SSH_TTY|XAUTHORITY|SSH_AUTH_SOCK).*?)=(.*?)$' 'set -gx $1 "$2"' | source
        # Update the GPG_TTY variable.
        set -gx GPG_TTY (tty)
    end
end

# OS Specific
set -l os (uname -s)
# WSL
if uname -a | grep -q WSL2
    set -gx BROWSER "/mnt/c/Program\ Files/Mozilla\ Firefox/firefox.exe"
else if test $os = Darwin
    set -gx BROWSER "/Applications/Arc.app/Contents/MacOS/Arc"
    # iTerm2 Shell Integration
    source ~/.iterm2_shell_integration.fish
end

# Set default editor to neovim.
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx SUDO_EDITOR nvim

# How many commands to wait before removing bad commands from shell history.
# Reference: https://github.com/meaningful-ooo/sponge#-adjusting-delay
set -gx sponge_delay 10

# Make Ctrl-H work in tmux pane navigation.
bind -M insert \ch "tmux select-pane -L"

# History search.
bind -M insert \cp history-search-backward
bind -M insert \cn history-search-forward
bind -M visual \cp history-search-backward
bind -M visual \cn history-search-forward

# Easier autocomplete.
bind -M insert \cy accept-autosuggestion

# Fix gopls install for nvim.
# Reference: https://stackoverflow.com/questions/54415733/getting-gopath-error-go-cannot-use-pathversion-syntax-in-gopath-mode-in-ubun
set -gx GO111MODULE on

# Use .gitignore for fzf
set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --exclude .git --follow'
set -gx FZF_CTRL_T_COMMAND "command fd --follow \$dir --type f --hidden --exclude .git 2> /dev/null | sed '1d; s#^\./##'"
set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --exclude .git --follow'

source $HOME/.config/fish/fzf-key-bindings.fish

set -gx RIPGREP_CONFIG_PATH $HOME/.config/ripgrep.rc

set -gx BOB_CONFIG $HOME/.config/bob/config.json

# apt aliases
abbr -a aptupd "sudo nala update"
abbr -a aptupgd "sudo nala upgrade && sudo nala autoremove"
abbr -a aptinst "sudo nala install"
abbr -a aptrm "sudo nala remove"

# git aliases
# TODO: Execute all commands with -S.
abbr -a gcom "git checkout master"
abbr -a gpo "git pull -S origin"
abbr -a gp "git push"
abbr -a gpf "git push --force-with-lease"
abbr -a gcm "git commit -S -m"
abbr -a gca "git commit -S --amend --no-edit"
abbr -a ga "git add"
abbr -a gst "git status --short"
abbr -a gco "git checkout"
abbr -a gcn "git checkout -b pcardenas/"
abbr -a gbd "git branch -d"
abbr -a gbl "git branch -l"
abbr -a gsp "git stash push"
abbr -a gspo "git stash pop"
abbr -a gsl "git stash list"
abbr -a gsd "git stash drop"
abbr -a gsa "git stash apply"
abbr -a gcp "git cherry-pick -S"
abbr -a nuke 'git rm --cached -r .; and GIT_LFS_SKIP_SMUDGE=1 git reset --hard'
abbr -a lg lazygit

# Starship
abbr -a p "starship prompt"
set -gx STARSHIP_LOG error

# Don't accidentally run vim
abbr -a vim nvim
abbr -a vi nvim
abbr -a v nvim

# Got into a broken state once when didn't detach client. Keeping this here in case it happens again.
# abbr -a t "tmux detach-client; and tmux attach; or tmux"
# abbr -a ta "tmux attach -d -t"
abbr -a t "tmux attach; or tmux"
abbr -a ta "tmux attach -t"

abbr -a sofi "source $HOME/.config/fish/config.fish"
abbr -a cheznous "chezmoi git pull -- --rebase; and chezmoi merge-all"
abbr -a chezvous "chezmoi git pull -- --rebase; and chezmoi --interactive apply"
abbr -a ce "chezmoi edit"
abbr -a ca "chezmoi re-add"

# VSCode shell integration
string match -q "$TERM_PROGRAM" vscode
and . (code --locate-shell-integration-path fish)

# ROS setup
if test -e /opt/ros/noetic/setup.bash
    bass source /opt/ros/noetic/setup.bash
end


# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/petercardenas/google-cloud-sdk/path.fish.inc' ]
    . '/Users/petercardenas/google-cloud-sdk/path.fish.inc'
end
