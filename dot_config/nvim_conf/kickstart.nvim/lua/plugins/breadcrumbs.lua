---@type dropbar_configs_t
---@diagnostic disable-next-line: missing-fields
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
    update_events = {
      buf = {
        'OptionSet',
        -- `OptionSet modified` reports `buf=0`, so saves via `vim.cmd('w')`
        -- need an explicit write event to refresh the modified marker.
        'BufWritePost',
        'FileChangedShellPost',
        'TextChanged',
        'TextChangedI',
        'ModeChanged',
      },
    },
    sources = function(buf, _)
      local sources = require('dropbar.sources')
      if vim.bo[buf].ft == 'markdown' then
        return {
          sources.path,
          sources.markdown,
        }
      end
      local bufname = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].buftype == 'terminal' or bufname:match('octo://') then
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
  'PeterCardenas/dropbar.nvim',
  branch = 'master',
  upstream = 'Bekaboo/dropbar.nvim',
  upstream_branch = 'master',
  event = { 'BufReadPre', 'BufNewFile' },
  -- optional, but required for fuzzy finder support
  dependencies = {
    'nvim-telescope/telescope-fzf-native.nvim',
  },
  config = function()
    require('dropbar').setup(DROPBAR_CONFIG)
  end,
}
