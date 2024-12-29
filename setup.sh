#!/usr/bin/env bash

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
	echo "Script should not be run as root"
	exit 1
fi

function install_ghostty() {
	if [ "$(uname)" == "Linux" ]; then
		git clone personal-github.com:ghostty-org/ghostty.git ~/thirdparty/ghostty
		pushd ~/thirdparty/ghostty || exit 1
		zvm use v0.13.0
		zig build -p "$HOME/.local" -Doptimize=ReleaseFast
		popd || exit 1
	elif [ "$(uname)" == "Darwin" ]; then
		gh release --repo ghostty-org/ghostty download tip --pattern ghostty-macos-universal.zip
		unzip ghostty-macos-universal.zip -d /Applications
	fi
}

function setup_ubuntu() {
	sudo apt update -y
	sudo apt install -y nala
	dpkg_packages=(
		curl
		wget
		git-lfs
		openssh-server
		gnupg2
		pinentry-tty
		pip
		et
		python3.10-venv
		jq
		flameshot
		fortune
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
		# Used for 3rd/image.nvim plugin
		lib-imagemagickwand-dev
		# For lazy.nvim
		luarocks
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

	# Git
	dpkg_third_party+=(
		git
	)
	sudo add-apt-repository ppa:git-core/ppa

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

	# Speedtest CLI
	dpkg_third_party+=(
		speedtest
	)
	curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash

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
		btop
		et
		fish
		fortune
		gh
		git-lfs
		gnupg2
		go
		vim
		wget
		# Needed for building Neovim, among other things
		cmake gettext-runtime
		# Used for 3rd/image.nvim plugin
		imagemagick
		# For lazy.nvim
		luarocks
		# MacOS/iOS development in neovim
		xcode-build-server
	)
	sudo port install "${ports[@]}"
}

function setup_unix() {
	# Install pnpm
	curl -fsSL https://get.pnpm.io/install.sh | sh -
	# Install Node via pnpm
	pnpm env use --global lts

	# Install zig version manager
	curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash

	# Install Starship prompt
	curl -sS https://starship.rs/install.sh | sh -s -- -y

	# Setup tmux plugin manager (tpm)
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

	# Add ghostty shaders
	git clone https://github.com/m-ahdal/ghostty-shaders.git ~/thirdparty/ghostty-shaders

	# Change login shell to fish
	sudo chsh -s /usr/bin/fish

	# Install chezmoi
	sh -c "$(curl -fsLS get.chezmoi.io)"
	chezmoi completion fish >~/.config/fish/completions/chezmoi.fish

	# Install fzf
	git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	~/.fzf/install --xdg --no-bash --no-zsh --no-key-bindings --no-update-rc --no-completion

	# Setup rust
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

	# Install cargo binstall
	curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

	# Install rust packages with cargo binstall
	rust_packages=(
		git-delta
		bob-nvim
		fd-find
		bat
		ttyper
		stylua
		tree-sitter-cli
		silicon
		yazi-fm yazi-cli
	)
	cargo binstall --no-confirm "${rust_packages[@]}"
	# --features isn't supported by cargo binstall
	cargo install --features 'pcre2' ripgrep

	# Setup delta/bat theme
	mkdir -p "$(bat --config-dir)/themes"
	pushd "$(bat --config-dir)/themes" || exit 1
	wget https://github.com/folke/tokyonight.nvim/raw/main/extras/sublime/tokyonight_storm.tmTheme
	bat cache --build
	popd || exit 1

	# Install go packages
	go install github.com/jesseduffield/lazygit@latest
	go install golang.org/x/lint/golint@latest
	go install github.co/iximiuz/cdebug@latest

	# Manually cloned tooling
	mkdir -p "$HOME/thirdparty"
	pushd "$HOME/thirdparty" || exit 1

	# Install tmux
	wget https://github.com/tmux/tmux/releases/download/3.4/tmux-3.4.tar.gz
	tar xvzf tmux-3.4.tar.gz
	pushd tmux-3.4 || exit
	./configure && make && sudo make install
	popd || exit 1

	# Exit thirdparty to $HOME
	popd || exit 1

	# Install kitty and kitten cli
	curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

	# Clone and apply dotfiles
	cat <<EOF >"$HOME/.ssh/config"
Host personal-github.com
 	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_personal
EOF
	ssh-keygen -t ed25519 -C "111733365+PeterCardenas@users.noreply.github.com" -f "$HOME/.ssh/id_ed25519_personal"
	gh auth login --git-protocol ssh --hostname github.com
	gh ssh-key add "$HOME/.ssh/id_ed25519_personal.pub" --title "Automated ssh key upload"
	chezmoi init --apply personal-github.com:PeterCardenas/dotfiles.git

	# Post-dotfiles setup
	fish -c "fisher update"
	bob sync
	cp ~/fonts/* ~/.fonts
	fc-cache -f -v

	install_ghostty

	bob complete fish >"$HOME/.config/fish/completions/bob.fish"

	# Add some autogenerated completions
	fish_update_completions
}

if [ "$(uname)" == "Linux" ]; then
	setup_ubuntu
elif [ "$(uname)" == "Darwin" ]; then
	setup_mac
else
	echo "Unsupported OS $(uname)"
	exit 1
fi
setup_unix
