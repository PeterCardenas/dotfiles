-- Install package manager
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local output = vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { output, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- Remove sync due to conflict with leap.nvim, and it + others since using these commands is usually a mistake.
local default_commands = require('lazy.view.config').commands
-- TODO: Only disable the install/update tabs, but keep the commands.
default_commands.sync = nil

-- Add plugins for lazy.nvim.
require('lazy').setup({
  -- Detect tabstop and shiftwidth automatically
  {
    'tpope/vim-sleuth',
    event = { 'BufReadPre', 'BufNewFile' },
  },

  -- TODO: Unsure if this is causing delays in startup rather than requiring the plugin configs manually.
  { import = 'plugins' },
}, {
  change_detection = {
    -- TODO: 1 day this will be useful, but today is not that day.
    enabled = false,
    notify = false,
  },
  install = { colorscheme = { 'tokyonight' } },
  performance = {
    cache = {
      enabled = true,
    },
    rtp = {
      disabled_plugins = {
        'gzip',
        'rplugin',
        'netrwPlugin',
        'tarPlugin',
        'tohtml',
        'tutor',
        'zipPlugin',
      },
    },
  },
  ui = {
    border = 'rounded',
    title = 'Lazy Plugins',
  },
})
