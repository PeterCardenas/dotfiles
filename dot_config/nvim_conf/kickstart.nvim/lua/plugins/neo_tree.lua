vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Open NvimTree on startup with directory',
  group = vim.api.nvim_create_augroup('nvim_tree_start', { clear = true }),
  callback = function()
    local stats = vim.loop.fs_stat(vim.api.nvim_buf_get_name(0))
    if stats and stats.type == 'directory' then
      local num_bufs = #vim.api.nvim_list_bufs()
      if num_bufs == 1 then
        -- Open NvimTree with the current file's directory
        require('nvim-tree.actions.tree').open.fn({
          path = vim.fn.expand('%:p:h'),
        })
      else
        require('mini.files').open(vim.fn.expand('%:p:h'))
      end
    end
  end,
})

local nmap = require('utils.keymap').nmap

nmap('Toggle file explorer tree', 'ot', function()
  require('nvim-tree.actions').tree.toggle.fn({ find_file = true })
end)

nmap('Toggle mini file explorer', 'oo', function()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_filename = vim.api.nvim_buf_get_name(current_buf)
  require('mini.files').open(current_buf_filename)
end)

---@type LazyPluginSpec[]
return {
  -- File explorer as a tree
  {
    'nvim-tree/nvim-tree.lua',
    lazy = true,
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    config = function()
      require('nvim-tree').setup({
        update_focused_file = {
          enable = true,
        },
      })
    end,
  },

  -- File explorer as an editable buffer
  {
    'stevearc/oil.nvim',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    lazy = true,
    config = function()
      require('oil').setup({
        default_file_explorer = true,
        view_options = {
          show_hidden = true,
        },
      })
    end,
  },

  -- File explorer as a buffer and as a tree view
  {
    'echasnovski/mini.files',
    version = false,
    lazy = true,
    config = function()
      require('mini.files').setup({
        windows = {
          preview = true,
        },
        mappings = {
          go_in = 'L',
          go_in_plus = '<CR>',
          go_out = 'H',
          go_out_plus = '-',
          synchronize = '<leader>s',
        },
      })
    end,
  },
}
