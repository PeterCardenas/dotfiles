function fish_greeting
  if [ ! -x fortune ]
    return 0
  end
  echo
  set_color yellow
  fortune
  set_color normal
end

# Add utility for ssh port forwarding
function pf --description 'ssh port forward'
  ssh_args = ""
  for port in $argv
    set ssh_args $ssh_args $port:$port
  end
  ssh -vfNL $ssh_args
end

source "$HOME"/.config/fish/colors.fish

# Fix Ctrl-Backspace (fix currently doesn't work)
bind \b backward-kill-word

# OS Specific
set -l os (uname -s)
# WSL
if uname -a | grep -q WSL2
  set -gx BROWSER "/mnt/c/Program\ Files/Mozilla\ Firefox/firefox.exe"
else if test $os = Darwin
  set -gx BROWSER /Applications/Firefox.app/Contents/MacOS/firefox
  # iTerm2 Shell Integration
  source ~/.iterm2_shell_integration.fish
end

# Use .gitignore for fzf
set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --exclude .git --follow'
set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --exclude .git --follow'

source $HOME/.config/fish/fzf-key-bindings.fish

set -gx GPG_TTY "(tty)"

set -gx RIPGREP_CONFIG_PATH $HOME/.config/ripgrep.rc

# apt aliases
abbr -a aptupd "sudo apt update -y"
abbr -a aptupgd "sudo apt upgrade -y && sudo apt autoremove -y"
abbr -a aptinst "sudo apt install -y"
abbr -a aptrm "sudo apt remove -y"

# git aliases
abbr -a gcom "git checkout master"
# abbr -a gpm "git pull -S origin master"
abbr -a gpm "git fetch origin master:master && git rebase master"
# abbr -a gpo "git pull -S origin"
abbr -a gpo "git pull origin"
abbr -a gp "git push --no-verify"
abbr -a gpf "git push --no-verify --force-with-lease"
# abbr -a gcm "git commit -S -m"
abbr -a gcm "git commit -m"
# abbr -a gca "git commit -S --amend --no-edit"
abbr -a gca "git commit --amend --no-edit"
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
# abbr -a gcp "git cherry-pick -S"
abbr -a gcp "git cherry-pick"
abbr -a nuke 'git rm --cached -r .; and GIT_LFS_SKIP_SMUDGE=1 git reset --hard'
abbr -a lg "lazygit"

abbr -a p "starship prompt"

abbr -a vim "nvim"

abbr -a t "tmux detach-client; tmux a; or tmux"

abbr -a sofi "source $HOME/.config/fish/config.fish"
abbr -a cheznous "chezmoi git pull -- --rebase; and chezmoi merge-all"
abbr -a chezvous "chezmoi git pull -- --rebase; and chezmoi --interactive apply"
abbr -a ce "chezmoi edit"
abbr -a ca "chezmoi re-add"

# VSCode shell integration
string match -q "$TERM_PROGRAM" "vscode"
and . (code --locate-shell-integration-path fish)

# ROS setup
if test -e /opt/ros/noetic/setup.bash
  bass source /opt/ros/noetic/setup.bash
end

# Start Starship
starship init fish | source

