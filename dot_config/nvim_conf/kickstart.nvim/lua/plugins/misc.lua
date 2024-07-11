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
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory' },
    config = function()
      require('diffview').setup({})
    end,
  },

  {
    'nvim-tree/nvim-web-devicons',
    lazy = true,
    config = function()
      ---@param icon_name string
      local function get_config_icon(icon_name)
        return {
          icon = '',
          color = '#4288b9',
          name = icon_name,
        }
      end
      require('nvim-web-devicons').setup({
        override_by_filename = {
          ['.bazelrc'] = get_config_icon('Bazelrc'),
        },
        override_by_extension = {
          rc = get_config_icon('Rc'),
        },
      })
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
        include_declaration = { 'lsp_definitions' },
      })
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
      ---@diagnostic disable-next-line: missing-fields
      require('notify').setup({
        top_down = false,
      })
      require('noice').setup({
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
            ['vim.lsp.util.stylize_markdown'] = true,
            ['cmp.entry.get_documentation'] = true,
          },
        },
        routes = {
          -- Filter out some unnecessary notifications
          {
            filter = {
              event = 'msg_show',
              any = {
                { find = '%d+L, %d+B' },
                { find = '; after #%d+' },
                { find = '; before #%d+' },
                { find = '%d fewer lines' },
                { find = '%d more lines' },
                { find = 'No lines in buffer' },
              },
            },
            opts = { skip = true },
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = false, -- use a classic bottom cmdline for search
          command_palette = true, -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          lsp_doc_border = true, -- add a border to hover docs and signature help
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
                hint = '󰛩 ',
              },
            },
          },
          lualine_c = {
            'filename',
          },
          lualine_x = {
            {
              ---@diagnostic disable-next-line: undefined-field
              require('noice').api.status.mode.get,
              cond = function()
                ---@diagnostic disable-next-line: undefined-field
                local has_status = require('noice').api.status.mode.has()
                if not has_status then
                  return false
                end
                ---@type string
                ---@diagnostic disable-next-line: undefined-field
                local status = require('noice').api.status.mode.get()
                return vim.startswith(status, 'recording')
              end,
              color = { fg = '#ff9e64' },
            },
            'encoding',
            'fileformat',
            'filetype',
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
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('Comment').setup({
        pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),
      })
    end,
  },

  -- Better commentstring (helps commenting in tsx/jsx files)
  {
    event = { 'BufReadPre', 'BufNewFile' },
    'JoosepAlviste/nvim-ts-context-commentstring',
    dependencies = 'nvim-treesitter',
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('ts_context_commentstring').setup({
        enable_autocmd = false,
      })
    end,
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
    lazy = true,
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
    event = { 'BufRead' },
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
      require('leap').opts.substitute_chars = { ['{'] = 'b', ['}'] = 'b', ['('] = 'p', [')'] = 'p', ['['] = 'b', [']'] = 'b' }
    end,
  },

  -- Status column
  {
    'luukvbaal/statuscol.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local builtin = require('statuscol.builtin')

      require('statuscol').setup({
        foldfunc = 'builtin',
        ft_ignore = { 'dashboard', 'NvimTree', 'help' },
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

  -- Profile lua neovim config.
  {
    'stevearc/profile.nvim',
    cond = function()
      return os.getenv('NVIM_PROFILE') ~= nil
    end,
    -- MUST be the first plugin to load.
    -- TODO: this doesn't ensure that with other lazy=false plugins.
    priority = 100000,
    lazy = false,
    config = function()
      local profile_env = os.getenv('NVIM_PROFILE')
      if not profile_env then
        error('NVIM_PROFILE is not set')
        return
      end
      require('profile').instrument_autocmds()
      if profile_env:lower():match('^start') then
        require('profile').start('*')
      else
        require('profile').instrument('*')
      end
      local function toggle_profile()
        local prof = require('profile')
        if prof.is_recording() then
          prof.stop()
          vim.ui.input({ prompt = 'Save profile to:', completion = 'file', default = '/tmp/neovim_lua_profile.json' }, function(filename)
            if filename then
              prof.export(filename)
              vim.notify(string.format('Wrote %s', filename))
            end
          end)
        else
          prof.start('*')
        end
      end
      vim.keymap.set('', '<f1>', toggle_profile)
    end,
  },

  -- Add ghostty completion + syntax
  {
    name = 'MacOS Ghostty',
    dir = '/Applications/Ghostty.app/Contents/Resources/vim/vimfiles/',
    lazy = false,
    cond = function()
      return vim.fn.executable('ghostty') == 1 and vim.fn.has('mac') == 1
    end,
  },
  {
    name = 'Linux Ghostty',
    dir = os.getenv('HOME') .. '/.local/share/vim/vimfiles/',
    lazy = false,
    cond = function()
      return vim.fn.executable('vim') == 1 and vim.fn.has('linux') == 1
    end,
  },
}
