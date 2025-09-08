-- Install package manager
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local output = vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/PeterCardenas/lazy.nvim.git',
    '--branch=dev', -- branch with patches
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

-- HACK: Accomodate using ssh alias as git url format.
local old_open = require('lazy.util').open
require('lazy.util').open = function(url, opts) ---@param url string
  url = url:gsub('personal%-github%.com:', 'https://github.com/')
  return old_open(url, opts)
end

-- Add plugins for lazy.nvim.
require('lazy').setup({
  -- Detect tabstop and shiftwidth automatically
  {
    'tpope/vim-sleuth',
    event = { 'BufReadPre', 'BufNewFile' },
  },

  -- TODO: Unsure if this is causing delays in startup rather than requiring the plugin configs manually.
  { import = 'plugins' },
  {
    'PeterCardenas/lazy.nvim',
    branch = 'dev',
  },
}, {
  change_detection = {
    -- TODO: 1 day this will be useful, but today is not that day.
    enabled = false,
    notify = false,
  },
  install = { colorscheme = { 'tokyonight' } },
  git = {
    url_format = 'personal-github.com:%s.git',
  },
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
