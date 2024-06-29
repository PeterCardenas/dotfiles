#!/usr/bin/env bash

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
	echo "Script should not be run as root"
	exit 1
fi

function setup_ubuntu() {
	sudo apt update -y
	sudo apt install -y nala
	dpkg_packages=(
		curl
		wget
		git
		git-lfs
		openssh-server
		gnupg2
		xclip
		pinentry-tty
		fzf
		pip
		et
		python3.10-venv
		jq
		flameshot
		peek
		ccls
		btop
		# Used for neovim file watching on Linux
		fswatch
		# Needed for building Neovim, among other things
		cmake gettext
		# Needed for NAS mounting
		cifs-utils
		# Unknown group
		software-properties-common apt-transport-https ca-certificates
		# Unknown group
		libevent-dev ncurses-dev build-essential bison pkg-config
	)
	sudo nala remove -y xsel
	sudo nala install -y "${dpkg_packages[@]}"

	# Setup third-party repositories
	# Docker
	dpkg_third_party+=(
		docker-ce
		docker-ce-cli
		containerd.io
		docker-buildx-plugin
		docker-compose-plugin
	)
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
	$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
		sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	# Fish shell
	dpkg_third_party+=(
		fish
	)
	sudo apt-add-repository ppa:fish-shell/release-3

	# GitHub CLI
	dpkg_third_party+=(
		gh
	)
	wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
	chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
	echo "deb [arch=(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null

	# Google Chrome
	dpkg_third_party=(
		google-chrome-stable
	)
	curl -fSsL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | tee /usr/share/keyrings/google-chrome.gpg >/dev/null
	echo deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main | tee /etc/apt/sources.list.d/google-chrome.list

	sudo nala update -y
	sudo nala install -y "${dpkg_third_party[@]}"

	# Setup golang
	wget https://go.dev/dl/go1.22.4.linux-amd64.tar.gz
	tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
	rm go1.22.4.linux-amd64.tar.gz
}

function setup_mac() {
	# Install MacPorts
	curl -O https://github.com/macports/macports-base/releases/download/v2.9.3/MacPorts-2.9.3.tar.bz2
	tar xvjf MacPorts-2.9.3.tar.bz2
	cd MacPorts-2.9.3
	./configure && make && sudo make install
	cd ..
	rm -rf MacPorts-2.9.3*
	sudo port -v selfupdate

	# Install MacPorts packages
	ports=(
		bat
		btop
		et
		fd
		fish
		fortune
		fzf
		gh
		git-lfs
		gnupg2
		go
		vim
		wget
		# Needed for building Neovim, among other things
		cmake gettext-runtime
	)
	sudo port install "${ports[@]}"
}

function setup_unix() {
	# Install pnpm
	curl -fsSL https://get.pnpm.io/install.sh | sh -

	# Install zig version manager
	curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

	# Install Starship prompt
	curl -sS https://starship.rs/install.sh | sh

	# Setup tmux plugin manager (tpm)
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

	# Change login shell to fish
	sudo chsh -s /usr/bin/fish

	# Install chezmoi
	sh -c "$(curl -fsLS get.chezmoi.io)"

	# Setup rust
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	rust_packages=(
		git-delta
		ripgrep
		bob-nvim
		fd-find
		bat
		ttyper
		stylua
		tree-sitter-cli
	)
	cargo install "${rust_packages[@]}"

	# Install go packages
	go install github.com/jesseduffield/lazygit@latest
	go install golang.org/x/lint/golint@latest
	go install github.co/iximiuz/cdebug@latest

	# Manually cloned tooling
	mkdir -p "$HOME/thirdparty"
	pushd "$HOME/thirdparty" || exit

	# Install tmux
	wget https://github.com/tmux/tmux/releases/download/3.4/tmux-3.4.tar.gz
	tar xvzf tmux-3.4.tar.gz
	pushd tmux-3.4 || exit
	./configure && make && sudo make install
	popd || exit

	popd || exit

	# Clone and apply dotfiles
	cat <<EOF >"$HOME/.ssh/config"
Host personal-github.com
 	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_personal
EOF
	ssh-keygen -t ed25519 -C "111733365+PeterCardenas@users.noreply.github.com" -f "$HOME/.ssh/id_ed25519_personal"
	gh auth login
	gh ssh-key add "$HOME/.ssh/id_ed25519_personal.pub" --title "Automated ssh key upload"
	chezmoi init --apply personal-github.com:PeterCardenas/dotfiles.git

	# Post-dotfiles setup
	fish -c "fisher update"
	bob sync
	cp ~/fonts/* ~/.fonts
	fc-cache -f -v
}

if [ "$(uname)" == "Linux" ]; then
	setup_ubuntu
elif [ "$(uname)" == "Darwin" ]; then
	echo "macOS specific setup not implemented"
else
	echo "Unsupported OS $(uname)"
	exit 1
fi
setup_unix
