# Install vim-plug
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# Setup YCM for vim completion
sudo apt install -y python3-dev
sudo apt install -y mono-complete golang nodejs openjdk-17-jdk openjdk-17-jre npm
pushd ~/.vim/plugged/YouCompleteMe
python3 install.py --all
popd

