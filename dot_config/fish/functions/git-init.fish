function git-init --description 'Initialize a git repository for personal use' -a repo_name
    git-init-common PeterCardenas "$HOME/.local/share/chezmoi/.git" personal-github.com "$repo_name"
end
