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
        local parent_dir = fzf_history_dir .. '/' .. type
        if vim.fn.isdirectory(parent_dir) == 0 then
          vim.fn.mkdir(parent_dir, 'p')
        end
        return parent_dir .. '/' .. cwd:gsub('/', '_')
      end
      -- Clear fuzzy toggle for grep
      require('fzf-lua.defaults').defaults.grep.actions = {}
      -- TODO: Make regex match case insensitive
      -- TODO: frecency support, reference: https://www.reddit.com/r/neovim/comments/1hmoa2z/comment/m3vkvba/
      require('fzf-lua').setup({
        -- TODO: Fix no write since last change
        -- 'hide',
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
            ['--scheme'] = 'path',
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
