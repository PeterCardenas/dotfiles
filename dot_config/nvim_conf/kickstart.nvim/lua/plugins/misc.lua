---@type LazyPluginSpec[]
return {
  -- Add a background color to colors defined in css.
  -- {
  --   'norcalli/nvim-colorizer.lua',
  --   event = { "BufReadPre", "BufNewFile" },
  --   config = function()
  --     require('colorizer').setup()
  --   end,
  -- },

  -- Enable editing the highlight colors and saving them to a file.
  -- {
  --   'Djancyp/custom-theme.nvim',
  --   event = { "BufReadPre", "BufNewFile" },
  --   config = function()
  --     require('custom-theme').setup()
  --   end,
  -- },

  -- Diffviewer and Mergetool
  {
    'sindrets/diffview.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      require('diffview').setup({})
    end,
  },

  -- Better picker for LSP references, definitions, and diagnostics.
  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    lazy = true,
    config = function()
      require('trouble').setup({
        use_diagnostic_signs = true,
        position = 'right',
        width = 100,
        auto_open = false,
        auto_close = true,
        action_keys = {
          toggle_fold = { 'zc', 'zo', 'o' },
        },
      })
    end,
  },

  -- Smooth scrolling
  {
    'karb94/neoscroll.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      require('neoscroll').setup({
        cursor_scrolls_alone = false,
        stop_eof = false,
      })
      local t = {}
      -- Syntax: t[keys] = {function, {function arguments}}
      t['<C-u>'] = { 'scroll', { '-vim.wo.scroll', 'true', '150' } }
      t['<C-d>'] = { 'scroll', { 'vim.wo.scroll', 'true', '150' } }
      t['<C-b>'] = { 'scroll', { '-vim.api.nvim_win_get_height(0)', 'true', '75' } }
      t['<C-f>'] = { 'scroll', { 'vim.api.nvim_win_get_height(0)', 'true', '75' } }
      t['<C-y>'] = { 'scroll', { '-0.10', 'false', '75' } }
      t['<C-e>'] = { 'scroll', { '0.10', 'false', '75' } }
      t['zt'] = { 'zt', { '75' } }
      t['zz'] = { 'zz', { '75' } }
      t['zb'] = { 'zb', { '75' } }

      require('neoscroll.config').set_mappings(t)
    end,
  },

  -- Delete buffers more reliably
  {
    'famiu/bufdelete.nvim',
    lazy = true,
  },

  -- Enable copilot
  {
    'zbirenbaum/copilot.lua',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup({
        suggestion = {
          auto_trigger = true,
          keymap = {
            accept = '<C-c>',
          },
        },
      })
    end,
  },

  -- Useful plugin to show you pending keybinds.
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    config = function()
      require('which-key').setup({
        disable = {
          filetypes = { 'TelescopePrompt' },
        },
      })
    end,
  },

  -- Better UI for select, notifications, popups, and many others.
  {
    'folke/noice.nvim',
    priority = 999,
    dependencies = {
      'MunifTanjim/nui.nvim',
      'rcarriga/nvim-notify',
    },
    config = function()
      require('noice').setup({
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
            ['vim.lsp.util.stylize_markdown'] = true,
            ['cmp.entry.get_documentation'] = true,
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = false,        -- use a classic bottom cmdline for search
          command_palette = true,       -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = true,            -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = false,       -- add a border to hover docs and signature help
        },
      })
    end,
  },

  -- Better code action menu
  {
    'aznhe21/actions-preview.nvim',
    lazy = true,
  },

  {
    -- Set lualine as statusline
    'nvim-lualine/lualine.nvim',
    -- See `:help lualine.txt`
    config = function()
      require('lualine').setup({
        options = {
          icons_enabled = true,
          component_separators = '|',
          section_separators = '',
          globalstatus = true,
        },
        sections = {
          lualine_b = {
            'branch',
            'diff',
            {
              'diagnostics',
              symbols = {
                error = ' ',
                warn = ' ',
                info = ' ',
                hint = '󰛩',
              },
            },
          },
        },
      })
    end,
  },

  {
    -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      require('ibl').setup({
        scope = {
          show_start = false,
          show_end = false,
        },
        indent = {
          char = '┊',
        },
      })
    end,
  },

  -- "gc" to comment visual regions/lines
  {
    'numToStr/Comment.nvim',
    opts = {},
    event = { 'BufReadPre', 'BufNewFile' },
  },

  -- Camel-case and snake-case motion
  { 'bkad/CamelCaseMotion', event = { 'BufReadPre', 'BufNewFile' } },

  -- Sticky scroll
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = 'nvim-treesitter',
    config = function()
      require('treesitter-context').setup({
        mode = 'topline',
        line_numbers = true,
      })
    end,
  },

  -- Ripgrep with file name filtering
  {
    'nvim-telescope/telescope-live-grep-args.nvim',
    dependencies = 'telescope.nvim',
    config = function()
      require('telescope').load_extension('live_grep_args')
    end,
  },

  -- Easy folding
  {
    'kevinhwang91/nvim-ufo',
    dependencies = {
      'kevinhwang91/promise-async',
    },
    event = { 'BufEnter' },
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('ufo').setup({
        provider_selector = function()
          return { 'treesitter', 'indent' }
        end,
      })
    end,
  },

  -- Fast motion commands
  {
    'ggandor/leap.nvim',
    dependencies = { 'tpope/vim-repeat' },
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      require('leap').add_default_mappings()
    end,
  },

  -- Status column
  {
    'luukvbaal/statuscol.nvim',
    config = function()
      local builtin = require('statuscol.builtin')

      require('statuscol').setup({
        foldfunc = 'builtin',
        ft_ignore = { 'dashboard', 'neo-tree', 'help' },
        segments = {
          { text = { builtin.foldfunc }, click = 'v:lua.ScFa' },
          {
            sign = { name = { 'Diagnostic' }, colwidth = 2 },
            click = 'v:lua.ScSa',
          },
          { text = { builtin.lnumfunc }, click = 'v:lua.ScLa' },
          {
            sign = { namespace = { 'gitsigns' }, maxwidth = 2, colwidth = 1, wrap = true },
            click = 'v:lua.ScSa',
          },
        },
      })
    end,
  },

  -- Add Pairs Automatically
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({
        check_ts = true,
      })
    end,
  },

  -- Persists sessions based on directory.
  {
    'Shatur/neovim-session-manager',
    event = 'BufWritePost',
    config = function()
      require('session_manager').setup({
        autoload_mode = require('session_manager.config').AutoloadMode.CurrentDir,
        autosave_ignore_dirs = { '~/', '~/Downloads', '/' },
      })
    end,
  },

  -- Add lazygit neovim integration.
  {
    lazy = true,
    'kdheepak/lazygit.nvim',
    -- optional for floating window border decoration
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    config = function()
      vim.g.lazygit_floating_window_scaling_factor = 1
    end,
  },

  {
    'sourcegraph/sg.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    config = function()
      require('sg').setup({})
    end,
  },
}
