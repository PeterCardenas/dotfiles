---@type dropbar_configs_t
local DROPBAR_CONFIG = {
  icons = {
    kinds = {
      symbols = {
        Folder = '',
      },
    },
    ui = {
      bar = {
        separator = '/',
      },
      menu = {
        indicator = '> ',
      },
    },
  },
  bar = {
    sources = function(buf, _)
      local sources = require('dropbar.sources')
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
      }
    end,
    enable = function(buf, win)
      return vim.fn.win_gettype(win) == '' and vim.wo[win].winbar == '' and vim.bo[buf].bt == '' and (buf and vim.api.nvim_buf_is_valid(buf) and true or false)
    end,
  },
  sources = {
    path = {
      ---Add custom icon when buffer is modified.
      ---@param sym dropbar_symbol_t
      ---@return dropbar_symbol_t
      modified = function(sym)
        sym.name = sym.name .. ' '
        sym.name_hl = 'DiagnosticWarn'
        return sym
      end,
    },
  },
}

vim.keymap.set({ 'n', 'v' }, '<C-o>', function()
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
