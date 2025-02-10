require('plugins.telescope.setup').create_keymaps()

---@type LazyPluginSpec[]
return {
  {
    'ibhagwan/fzf-lua',
    dependencies = {
      'echasnovski/mini.icons',
      'nvim-treesitter/nvim-treesitter',
    },
    cmd = { 'FzfLua' },
    config = function()
      local fzf_history_dir = vim.fn.stdpath('data') .. '/fzf-history'
      local cwd = vim.fn.getcwd()
      ---@param type string
      local function get_history_file(type)
        return fzf_history_dir .. '/' .. type .. '/' .. cwd:gsub('/', '_')
      end
      -- Clear fuzzy toggle for grep
      require('fzf-lua.defaults').defaults.grep.actions = {}
      require('fzf-lua').setup({
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
          cmd = require('plugins.telescope.setup').rg_files_cmd(true),
          fzf_opts = {
            ['--history'] = get_history_file('files'),
          },
        },
        grep = {
          git_icons = false,
          -- TODO: Make this hide ignored files by default once this can be toggled.
          cmd = require('plugins.telescope.setup').rg_words_cmd(true),
          multiprocess = true,
          multiline = 1,
          fzf_opts = {
            ['--history'] = get_history_file('grep'),
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
      })
    end,
  },
}
