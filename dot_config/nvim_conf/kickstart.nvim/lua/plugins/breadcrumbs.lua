---@type dropbar_configs_t
local DROPBAR_CONFIG = {
  icons = {
    kinds = {
      symbols = require('plugins.breadcrumbs.icons'),
    },
    ui = {
      bar = {
        separator = '> ',
      },
      menu = {
        indicator = '> ',
      },
    },
  },
  bar = {
    sources = function(buf, _)
      local sources = require('dropbar.sources')
      local utils = require('dropbar.utils')
      if vim.bo[buf].ft == 'markdown' then
        return {
          sources.path,
          sources.markdown,
        }
      end
      if vim.bo[buf].buftype == 'terminal' then
        return {
          sources.terminal,
        }
      end
      return {
        sources.path,
        utils.source.fallback({
          sources.lsp,
          sources.treesitter,
        }),
      }
    end,
  },
}
vim.keymap.set({ 'n', 'v', 'i' }, '<C-o>', function()
  require('dropbar.api').pick()
end, { desc = 'Focus on breadcrumbs' })
---@type LazyPluginSpec
return {
  'Bekaboo/dropbar.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  -- optional, but required for fuzzy finder support
  dependencies = {
    'nvim-telescope/telescope-fzf-native.nvim',
  },
  config = function()
    require('dropbar').setup(DROPBAR_CONFIG)
  end,
}
