require('local.chezmoi').setup(os.getenv('HOME') .. '/.local/share/chezmoi')
require('local.gh')
require('local.ghostty_navigation').setup()
