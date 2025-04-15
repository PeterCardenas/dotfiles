local Async = require('utils.async')
local Shell = require('utils.shell')
local PickerHelpers = require('plugins.telescope.setup')
PickerHelpers.create_keymaps()

---@type LazyPluginSpec[]
return {
  {
    'ibhagwan/fzf-lua',
    dependencies = {
      'echasnovski/mini.icons',
      'nvim-treesitter/nvim-treesitter',
      'nvim-treesitter/nvim-treesitter-context',
    },
    cmd = { 'FzfLua' },
    config = function()
      local fzf_history_dir = vim.fn.stdpath('data') .. '/fzf-history'
      local cwd = vim.fn.getcwd()
      ---@param type string
      local function get_history_file(type)
        local parent_dir = fzf_history_dir .. '/' .. type
        if vim.fn.isdirectory(parent_dir) == 0 then
          vim.fn.mkdir(parent_dir, 'p')
        end
        return parent_dir .. '/' .. cwd:gsub('/', '_')
      end
      -- TODO: Make regex match case insensitive
      require('fzf-lua').setup({
        'hide',
        keymap = {
          builtin = {
            ['<C-D>'] = 'preview-page-down',
            ['<C-U>'] = 'preview-page-up',
          },
        },
        winopts = {
          height = 0.98,
          width = 0.98,
        },
        previewers = {
          builtin = {
            treesitter = {
              context = true,
            },
          },
        },
        files = {
          git_icons = false,
          -- TODO: Make this hide ignored files by default once this can be toggled.
          cmd = PickerHelpers.rg_files_cmd(true),
          fzf_opts = {
            ['--history'] = get_history_file('files'),
            ['--scheme'] = 'path',
            ['--tiebreak'] = 'index',
          },
          actions = {
            ['default'] = {
              fn = function(selected, opts) ---@param selected string[]
                Async.void(function() ---@async
                  -- Remove icon with a the same hack fzf-lua uses: look for special nbsp character and delete until that character
                  local selection = selected[1]
                  ---@type integer
                  local idx = selection:match('.*' .. require('fzf-lua.utils').nbsp .. '()')
                  idx = idx == nil and 0 or idx
                  selection = selection:sub(idx)
                  local success, output = Shell.async_cmd('fre', { '--add', selection, '--store_name', PickerHelpers.get_fre_store_name('files') })
                  if not success then
                    vim.schedule(function()
                      vim.notify(table.concat(output, '\n'), vim.log.levels.ERROR, { title = 'Adding to fre failed' })
                    end)
                  end
                end)
                require('fzf-lua.actions').file_edit_or_qf(selected, opts)
              end,
            },
          },
        },
        grep = {
          git_icons = false,
          rg_opts = PickerHelpers.rg_words_opts(true),
          multiprocess = true,
          multiline = 1,
          fzf_opts = {
            ['--history'] = get_history_file('grep'),
            ['--scheme'] = 'path',
          },
        },
        oldfiles = {
          include_current_session = true,
          fzf_opts = {
            ['--history'] = get_history_file('oldfiles'),
          },
        },
        helptags = {
          fzf_opts = {
            ['--history'] = fzf_history_dir .. '/helptags',
          },
        },
        highlights = {
          fzf_opts = {
            ['--history'] = fzf_history_dir .. '/highlights',
          },
        },
      })
    end,
  },
}
