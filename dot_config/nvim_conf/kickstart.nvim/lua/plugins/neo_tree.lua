local File = require('utils.file')

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Open NvimTree on startup with directory',
  group = vim.api.nvim_create_augroup('nvim_tree_start', { clear = true }),
  callback = function(args)
    local buf = args.buf ---@type integer
    local stats = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
    if stats and stats.type == 'directory' then
      local num_bufs = #vim.api.nvim_list_bufs()
      if num_bufs == 1 then
        -- Open NvimTree with the current file's directory
        require('nvim-tree.actions.tree').open.fn({
          path = vim.fn.expand('%:p:h'),
        })
      else
        -- Close the newly opened buffer so that mini.files can be opened in a valid buffer.
        local dir = vim.fn.expand('%:p:h')
        require('bufdelete').bufdelete(buf)
        require('mini.files').open(dir)
      end
    end
  end,
})

---@param id string
---@param path string|fun(): string
---@param desc string
local function set_mark(id, path, desc)
  require('mini.files').set_bookmark(id, path, { desc = desc })
end
vim.api.nvim_create_autocmd('User', {
  pattern = 'MiniFilesExplorerOpen',
  callback = function()
    set_mark('w', vim.fn.getcwd, 'Working directory')
    set_mark('b', function()
      local cwd = vim.fn.getcwd()
      return cwd .. '/bazel-out/k8-fastbuild/bin'
    end, 'Bazel output directory')
    set_mark('r', function()
      local explorer_state = require('mini.files').get_explorer_state()
      if explorer_state == nil then
        return vim.fn.getcwd()
      end
      local cur_file = explorer_state.branch[#explorer_state.branch] ---@type string
      local buf = vim.uri_to_bufnr(vim.uri_from_fname(cur_file))

      local roots = {} ---@type string[]
      local lsp_clients = vim.lsp.get_clients({ bufnr = buf })
      for _, client in ipairs(lsp_clients) do
        local workspace = client.config.workspace_folders
        for _, ws in ipairs(workspace or {}) do
          roots[#roots + 1] = vim.uri_to_fname(ws.uri)
        end
        if client.root_dir then
          roots[#roots + 1] = client.root_dir
        end
      end
      roots = vim.tbl_filter(function(path)
        path = vim.fs.normalize(path)
        return path and cur_file:find(path, 1, true) == 1
      end, roots)
      table.sort(roots, function(a, b)
        return a:len() > b:len()
      end)
      return roots[1]
    end, 'LSP root directory')
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Add mini.files mappings',
  group = vim.api.nvim_create_augroup('mini_files_enter', { clear = true }),
  callback = function(args)
    local buf = args.buf ---@type integer
    local filetype = vim.api.nvim_get_option_value('filetype', { buf = buf })
    if filetype ~= 'minifiles' then
      return
    end
    vim.keymap.set('n', '<leader>q', function()
      require('mini.files').close()
    end, {
      buffer = buf,
    })
    vim.keymap.set('n', '<ESC>', function()
      require('mini.files').close()
    end, {
      buffer = buf,
    })
  end,
})

local nmap = require('utils.keymap').nmap

nmap('Toggle file explorer tree', 'ot', function()
  require('nvim-tree.actions').tree.toggle.fn({ find_file = true })
end)

nmap('Toggle mini file explorer', 'oo', function()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_filename = vim.api.nvim_buf_get_name(current_buf)
  if not File.file_exists(current_buf_filename) then
    local dirname = vim.fn.fnamemodify(current_buf_filename, ':h')
    require('mini.files').open(dirname)
    return
  end
  require('mini.files').open(current_buf_filename)
end)

---@type LazyPluginSpec[]
return {
  -- File explorer as a tree
  {
    'nvim-tree/nvim-tree.lua',
    lazy = true,
    config = function()
      require('nvim-tree').setup({
        view = {
          side = 'right',
        },
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
      'echasnovski/mini.icons',
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
          -- width_focus = 25,
          -- TODO: Only want to apply to file previews
          -- width_preview = 75,
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
