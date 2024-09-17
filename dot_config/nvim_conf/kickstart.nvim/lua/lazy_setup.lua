-- Install package manager
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  })
end
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

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
  ui = {
    border = 'rounded',
    title = 'Lazy Plugins',
  },
})
