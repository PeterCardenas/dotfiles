local Buf = require('utils.buf')
---@type LazyPluginSpec[]
return {
  -- Sticky scroll
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = 'nvim-treesitter',
    config = function()
      vim.api.nvim_set_hl(0, 'TreesitterContext', { link = 'Normal' })
      vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { foreground = '#3b4261', background = '#24283b' })
      require('treesitter-context').setup({
        mode = 'topline',
        line_numbers = true,
        max_lines = 10,
        separator = '─',
        multiwindow = true,
        zindex = 41,
        on_attach = function(bufnr)
          local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
          -- Default disable at 512KB
          local file_size_threshold = 1024 * 512
          -- YAML files can be handled at 1.75MB
          if filetype == 'yaml' then
            file_size_threshold = 1024 * 768 + 1024 * 1024
          end
          local is_enabled = not Buf.is_buf_large(bufnr, file_size_threshold)

          return is_enabled
        end,
      })
    end,
  },
  {
    -- Highlight, edit, and navigate code
    -- TODO: Use upstream when the following is merged: https://github.com/nvim-treesitter/nvim-treesitter/pull/7821
    'PeterCardenas/nvim-treesitter',
    branch = 'add-granular-if-statement-folds',
    event = { 'BufReadPre', 'BufNewFile' },
    cmd = { 'TSInstall', 'TSInstallSync' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
    },
    build = ':TSUpdate',
    config = function()
      -- [[ Configure Treesitter ]]
      -- See `:help nvim-treesitter`
      -- TODO: Use ~/.local/share/nvim/site for treesitter parsers using `parser_install_dir`
      require('nvim-treesitter.configs').setup({
        -- Add languages to be installed here that you want installed for treesitter
        ensure_installed = { 'c', 'cpp', 'go', 'lua', 'python', 'rust', 'tsx', 'javascript', 'typescript', 'vimdoc', 'vim', 'markdown', 'fish', 'latex' },

        -- Autoinstall languages that are not installed. Defaults to false (but you can change for yourself!)
        auto_install = false,
        modules = {},
        ignore_install = {},
        sync_install = false,

        highlight = {
          enable = true,
          disable = function(lang, bufnr)
            if lang == 'markdown' then
              require('snacks.image').setup()
            end
            -- TODO: Maybe use dockerfile treesitter highlighting when the following is fixed: https://github.com/camdencheek/tree-sitter-dockerfile/issues/51
            return (lang == 'yaml' and vim.api.nvim_buf_get_name(bufnr):match('template%.yaml$')) or lang == 'tmux' or lang == 'dockerfile'
          end,
        },
        indent = { enable = true },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<c-space>',
            node_incremental = '<c-space>',
            scope_incremental = '<c-s>',
            node_decremental = '<M-space>',
          },
        },
        textobjects = {
          select = {
            enable = true,
            lookahead = true, -- Automatically jump forward to textobj, similar to targets.vim
            keymaps = {
              -- You can use the capture groups defined in textobjects.scm
              ['aa'] = '@parameter.outer',
              ['ia'] = '@parameter.inner',
              ['af'] = '@function.outer',
              ['if'] = '@function.inner',
              ['ac'] = '@class.outer',
              ['ic'] = '@class.inner',
              ['ai'] = '@conditional.outer',
              ['ii'] = '@conditional.inner',
              ['gb'] = '@comment.outer',
            },
          },
          move = {
            enable = true,
            set_jumps = true, -- whether to set jumps in the jumplist
            goto_next_start = {
              [']f'] = '@function.outer',
              [']c'] = '@class.outer',
            },
            goto_next_end = {
              [']F'] = '@function.outer',
              [']C'] = '@class.outer',
            },
            goto_previous_start = {
              ['[f'] = '@function.outer',
              ['[c'] = '@class.outer',
            },
            goto_previous_end = {
              ['[F'] = '@function.outer',
              ['[C'] = '@class.outer',
            },
          },
        },
      })
      vim.treesitter.language.register('markdown', 'markdown.mdx')
      vim.treesitter.language.register('markdown', 'notify')
      vim.treesitter.language.register('markdown', 'octo')
    end,
  },
}
