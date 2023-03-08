function setup_mac
  # Setup MacPorts
  curl https://github.com/macports/macports-base/releases/download/v2.8.1/MacPorts-2.8.1.tar.gz | tar xzvf 
  pushd MacPorts-2.8.1
  ./configure; and make; and make install
  fish_add_path /opt/local/bin /opt/local/sbin
  port -v selfupdate
  popd
  rm -rf MacPorts-2.8.1

  # Install packages
  port install -y neovim
end

function setup_linux
  # Install packages
  apt install -y neovim
end

function setup
  # Install starship
  curl -sS https://starship.rs/install.sh | sh
end

# OS Specific
set -l os (uname -s)
if test $os = Darwin
  setup_mac
else if test $os = Linux
  setup_linux
end
setup
