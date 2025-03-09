#!/usr/bin/env bash

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
	echo "Script should not be run as root"
	exit 1
fi

function install_ghostty() {
	zvm use v0.13.0
	pushd $HOME/projects
	fish -c "clone personal ghostty-org/ghostty.git"
	pushd ghostty
	fish -c "setup_fork"
	git checkout working-state
	if [ "$(uname)" == "Linux" ]; then
		zig build -p "$HOME/.local" -Doptimize=ReleaseFast
	elif [ "$(uname)" == "Darwin" ]; then
		zig build -Doptimize=ReleaseFast
		pushd macos
		xcodebuild
		popd
		cp -r macos/build/Release/Ghostty.app /Applications
	fi
	popd
	popd
}

function setup_ubuntu() {
	sudo -B apt update -y
	sudo -B apt install -y nala
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
		# For generating compile_commands.json for ccls
		bear
	)
	sudo -B nala remove -y xsel
	sudo -B nala install -y "${dpkg_packages[@]}"

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
	echo \n "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \n	$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
		sudo -B tee /etc/apt/sources.list.d/docker.list >/dev/null

	# Fish shell
	dpkg_third_party+=(
		fish
	)
	sudo -B apt-add-repository ppa:fish-shell/release-4

	# Git
	dpkg_third_party+=(
		git
	)
	sudo -B add-apt-repository ppa:git-core/ppa

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
	curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo -B bash

	sudo -B nala update -y
	sudo -B nala install -y "${dpkg_third_party[@]}"

	# Setup golang
	wget https://go.dev/dl/go1.22.4.linux-amd64.tar.gz
	tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
	rm go1.22.4.linux-amd64.tar.gz
}

function setup_macos_defaults() {
	IS_AUTOHIDE="$(defaults read com.apple.dock autohide)"
	defaults write com.apple.dock autohide -bool true
	defaults write com.apple.dock show-recents -bool false
	# Do not want to override already set docked apps
	if [ "$IS_AUTOHIDE" == "1" ]; then
		defaults write com.apple.dock persistent-apps -array
	fi
	killall Dock
	# Tap to click
	defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
	defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
	defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
	defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
	defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
	echo "Disabling Spotlight indexing"
	sudo mdutil -a -i off
	# TODO: menubar: battery percent show, show seconds in clock, hide spotlight, siri
	# TODO: key repeat
	# TODO: map caps lock to escape
}

function install_macports() {
	if command -v port >/dev/null 2>&1; then
		echo "MacPorts already installed."
		return 0
	fi
	if [ -n "$(stat -q /opt/local/bin)" ]; then
		echo "Adding port to PATH"
		export PATH="/opt/local/bin:$PATH"
		return 0
	fi
	echo "Installing MacPorts"
	curl -LO https://github.com/macports/macports-base/releases/download/v2.9.3/MacPorts-2.9.3.tar.bz2
	tar xvjf MacPorts-2.9.3.tar.bz2
	pushd MacPorts-2.9.3
	./configure
	make
	sudo -B make install
	popd
	rm -rf MacPorts-2.9.3*
}

function setup_mac() {
	setup_macos_defaults
	if ! gcc --version >/dev/null 2>&1; then
		echo "Accepting XCode license"
		sudo -B xcodebuild -license accept
	fi
	XCODE_INSTALLED="$(
		xcode-select -p 1>/dev/null
		echo $?
	)"
	if [ "$XCODE_INSTALLED" == "2" ]; then
		xcode-select --install
		read -p "Press enter once finished"
	fi
	install_macports

	echo "Ensuring MacPorts version and port tree"
	sudo mkdir -p /opt/local/etc/macports
	sudo touch /opt/local/etc/macports/sources.conf
	sudo tee "/opt/local/etc/macports/sources.conf" >/dev/null <<EOF
rsync://bos.us.rsync.macports.org/macports/release/tarballs/ports.tar [default]
EOF

	mkdir -p $HOME/.macports
	touch $HOME/.macports/macports.conf
	cat <<EOF >"$HOME/.macports/macports.conf"
rsync_server="atl.us.rsync.macports.org"
rsync_dir="MacPorts/release/tarballs/base.tar"
EOF
	sudo -B port -v selfupdate

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
		vim +python311
		wget
		# Needed for building Neovim, among other things
		cmake gettext-runtime
		# Used for 3rd/image.nvim plugin
		imagemagick
		# For lazy.nvim
		lua-luarocks lua51
		# MacOS/iOS development in neovim
		xcode-build-server
		# MacOS bash version is wildly out of date
		bash
		# Build tmux and other c/cpp programs
		automake
		# tmux dependencies
		libevent libutf8proc
		# Generate compile_commands.json for ccls
		bear
	)
	# TODO: figure out how to actually skip interactive questions
	sudo -B port install -N "${ports[@]}"

	# Install ccls
	# TODO: Move later since it's less important and takes a while
	pushd $HOME/thirdparty
	wget https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-arm64-apple-macos11.tar.xz
	tar xzvf clang+llvm-18.1.8-arm64-apple-macos11.tar.xz
	git clone https://github.com/MaskRay/ccls.git
	pushd ccls
	cmake -S. -BRelease -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local/ -DCMAKE_PREFIX_PATH=$HOME/thirdparty/clang+llvm-18.1.8-arm64-apple-macos11/
	cmake --build Release
	cp Release/ccls $HOME/.local/bin/
	popd
	popd
}

function setup_unix() {
	mkdir -p $HOME/.local/share
	GROUP="$(id -gn)"
	sudo chown $USER:$GROUP $HOME/.local/share
	source $HOME/.zshrc
	if ! command -v pnpm >/dev/null 2>&1; then
		# Install pnpm
		curl -fsSL https://get.pnpm.io/install.sh | sh -
		source $HOME/.zshrc
	fi
	# Install Node via pnpm
	pnpm env use --global lts
	npm install -g typescript

	# Install zig version manager
	if ! command -v zvm >/dev/null 2>&1; then
		curl https://raw.githubusercontent.com/tristanisham/zvm/master/install.sh | bash
		source $HOME/.zshrc
	fi

	mkdir -p $HOME/.local/bin
	export PATH="$PATH:$HOME/.local/bin"
	# Install Starship prompt
	if ! command -v starship >/dev/null 2>&1; then
		curl -sS https://starship.rs/install.sh | sh -s -- -y --bin-dir=$HOME/.local/bin
	fi

	# Install tmux
	if ! command -v tmux >/dev/null 2>&1 || [[ "$(tmux -V 2>/dev/null | cut -d' ' -f2)" != "3.5a" ]]; then
		pushd $HOME/thirdparty
		wget https://github.com/tmux/tmux/releases/download/3.5a/tmux-3.5a.tar.gz
		tar xvzf tmux-3.5a.tar.gz
		pushd tmux-3.5a
		./configure --prefix=$HOME/.local --enable-utf8proc
		make
		make install
		popd
		popd
	fi

	# Setup tmux plugin manager (tpm)
	rm -rf ~/.tmux/plugins/tpm
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

	# Change login shell to fish
	FISH_LOCATION="$(which fish)"
	if ! grep -q "$FISH_LOCATION" /etc/shells; then
		echo "$FISH_LOCATION" | sudo tee -a /etc/shells
	fi
	chsh -s "$FISH_LOCATION"

	# Install chezmoi
	pushd "$HOME"
	sh -c "$(curl -fsLS get.chezmoi.io/lb)"
	popd

	# Install fzf
	rm -rf ~/.fzf
	git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
	~/.fzf/install --xdg --no-bash --no-zsh --no-key-bindings --no-update-rc --no-completion

	# Setup rust
	# TODO: we should always use rustup, currently fish is pulling in rust in macports, need to resolve
	if ! command -v cargo >/dev/null 2>&1; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
	fi
	export PATH="$PATH:$HOME/.cargo/bin"

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
		aichat
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
	go install github.com/iximiuz/cdebug@latest

	# Install kitty and kitten cli
	curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

	if [ ! -f "$HOME/.ssh/config" ]; then
		mkdir -p "$HOME/.ssh"
		touch "$HOME/.ssh/config"
		# Clone and apply dotfiles
		cat <<EOF >"$HOME/.ssh/config"
Host personal-github.com
 	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_personal
Host work-github.com
 	HostName github.com
	User git
	IdentityFile ~/.ssh/id_ed25519_work
EOF
	fi
	if [ ! -f "$HOME/.ssh/id_ed25519_personal" ]; then
		# TODO: use real/noreply email to not have ties with github
		ssh-keygen -t ed25519 -C "111733365+PeterCardenas@users.noreply.github.com" -f "$HOME/.ssh/id_ed25519_personal"
	fi
	if ! gh auth status; then
		gh auth login --git-protocol ssh --hostname github.com --skip-ssh-key
		# TODO: use bitwarden for storing a shared ssh key
		gh ssh-key add "$HOME/.ssh/id_ed25519_personal.pub" --title "Automated ssh key upload"
	fi
	chezmoi init --apply personal-github.com:PeterCardenas/dotfiles.git
	chezmoi git lfs install
	chezmoi git lfs pull
	chezmoi apply

	# Post-dotfiles setup
	fish -c "fisher update"
	export BOB_CONFIG=$HOME/.config/bob/config.json
	fish -c "vswitch kickstart.nvim"
	if [ "$(uname)" == "Linux" ]; then
		mkdir -p $HOME/.fonts
		cp $HOME/fonts/* $HOME/.fonts/
	elif [ "$(uname)" == "Darwin" ]; then
		mkdir -p $HOME/Library/Fonts
		cp $HOME/fonts/* $HOME/Library/Fonts/
	fi
	fc-cache -f -v
	$HOME/.tmux/plugins/tpm/bin/install_plugins
	chezmoi completion fish >~/.config/fish/completions/chezmoi.fish
	install_ghostty

	# Add aichat completions
	curl -L https://github.com/sigoden/aichat/raw/refs/heads/main/scripts/completions/aichat.fish -o ~/.config/fish/completions/aichat.fish

	rg --generate=complete-fish >"$HOME/.config/fish/completions/rg.fish"
	bob complete fish >"$HOME/.config/fish/completions/bob.fish"

	# Add some autogenerated completions
	fish -c "fish_update_completions"
	# TODO install nvim plugins, mason deps, treesitter deps
	# TODO: setup gpg
	# TODO: setup gnome
	# TODO: Setup fish-lsp
	# TODO: reboot
}

# TODO: install zen browser and setup configuration, maybe (always allow x to open) things?
mkdir -p $HOME/thirdparty
mkdir -p $HOME/projects
if [ "$(uname)" == "Linux" ]; then
	setup_ubuntu
elif [ "$(uname)" == "Darwin" ]; then
	setup_mac
else
	echo "Unsupported OS $(uname)"
	exit 1
fi
setup_unix
