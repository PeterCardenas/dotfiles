local async = require('utils.async')

---@param bufnr integer
---@param file_size_threshold integer
---@return boolean
local function is_buf_large(bufnr, file_size_threshold)
  local file_name = vim.api.nvim_buf_get_name(bufnr)
  local file_size = vim.fn.getfsize(file_name)
  return file_size > file_size_threshold
end

local large_file_group = vim.api.nvim_create_augroup('Disable Large File Plugins', { clear = true })
vim.api.nvim_create_autocmd('BufReadPre', {
  desc = 'Conditionally load plugins for large files',
  group = large_file_group,
  callback = function(args)
    --Disables at 512KB
    local should_disable = is_buf_large(args.buf, 1024 * 512)
    require('ibl').setup_buffer(args.buf, {
      enabled = not should_disable,
    })
  end,
})

vim.api.nvim_create_user_command('SiliconCopy', function()
  require('silicon').clip()
end, { nargs = 0, range = true })

vim.api.nvim_create_user_command('DiffviewPR', function()
  async.void(
    ---@async
    function()
      local success, default_branch = require('utils.git').get_default_branch()
      vim.schedule(function()
        if not success then
          vim.notify('Could not get default branch:\n' .. default_branch, vim.log.levels.ERROR)
          return
        end
        vim.cmd('DiffviewOpen origin/' .. default_branch .. '...HEAD')
      end)
    end
  )
end, { nargs = 0 })

vim.api.nvim_create_user_command('DiffviewCurrentFileHistory', function(opts)
  if opts.range == 0 then
    vim.cmd('DiffviewFileHistory %')
    return
  else
    vim.cmd([['<,'>DiffviewFileHistory %]])
  end
end, { nargs = 0, range = true })

vim.keymap.set({ 'n' }, '<leader>tr', function()
  local last_mode = require('trouble').last_mode
  require('trouble').open({ mode = last_mode })
end)

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
      require('diffview').setup({
        watch_index = false,
        show_help_hints = false,
        enhanced_diff_hl = true,
        view = {
          merge_tool = {
            layout = 'diff3_mixed',
            disable_diagnostics = false,
            winbar_info = true,
          },
        },
        file_panel = {
          win_config = {
            width = 50,
          },
        },
      })
    end,
  },

  -- Better picker for LSP references, definitions, and diagnostics.
  {
    'folke/trouble.nvim',
    dependencies = { 'echasnovski/mini.icons' },
    lazy = true,
    config = function()
      require('trouble').setup({
        focus = true,
        win = {
          type = 'split',
          position = 'right',
          size = {
            width = 0.5,
          },
        },
        auto_open = false,
        auto_close = true,
        auto_jump = true,
        keys = {
          ['<cr>'] = 'jump_close',
        },
        modes = {
          lsp_references = {
            params = {
              include_declaration = false,
            },
          },
        },
      })
    end,
  },

  -- Delete buffers more reliably
  {
    'famiu/bufdelete.nvim',
    lazy = true,
  },

  -- Copilot AI autocompletion
  {
    'zbirenbaum/copilot.lua',
    event = 'InsertEnter',
    cond = function()
      return require('utils.config').USE_COPILOT
    end,
    config = function()
      require('copilot').setup({
        suggestion = {
          auto_trigger = true,
          keymap = {
            accept = '<C-y>',
          },
        },
      })
    end,
  },

  -- Super fast AI autocompletion
  {
    'supermaven-inc/supermaven-nvim',
    event = 'InsertEnter',
    cond = function()
      return not require('utils.config').USE_COPILOT
    end,
    config = function()
      require('supermaven-nvim').setup({
        keymaps = {
          accept_suggestion = '<C-y>',
        },
        log_level = 'warn',
      })
      require('supermaven-nvim.api').use_free_version()
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

  --- Utility icons for files
  {
    'echasnovski/mini.icons',
    version = false,
    lazy = false,
    config = function()
      require('mini.icons').setup({
        filetype = {
          bazelrc = { glyph = '', hl = 'MiniIconsCyan' },
          rust = { glyph = '', hl = 'MiniIconsOrange' },
          typescript = { glyph = '', hl = 'MiniIconsBlue' },
          javascript = { glyph = '', hl = 'MiniIconsBlue' },
          ['markdown.mdx'] = { glyph = '󰍔', hl = 'MiniIconsGrey' },
          fish = { glyph = '󰈺', hl = 'MiniIconsOrange' },
          bash = { glyph = '', hl = 'MiniIconsGrey' },
          sh = { glyph = '', hl = 'MiniIconsGrey' },
          spectre_panel = { glyph = '', hl = 'MiniIconsOrange' },
        },
        file = {
          ['.babelrc'] = { glyph = '󰨥', hl = 'MiniIconsYellow' },
          ['.bazelignore'] = { glyph = '', hl = 'MiniIconsPurple' },
          ['.bazelversion'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['.nogo_config.json'] = { glyph = '󰟓', hl = 'MiniIconsCyan' },
          ['compile_commands.json'] = { glyph = '󰙲', hl = 'MiniIconsCyan' },
          ['pyproject.toml'] = { glyph = '', hl = 'MiniIconsCyan' },
          ['.swcrc'] = { glyph = '󰘦', hl = 'MiniIconsYellow' },
          ['tsconfig.json'] = { glyph = '', hl = 'MiniIconsBlue' },
          ['.npmrc'] = { glyph = '', hl = 'MiniIconsRed' },
          ['package.json'] = { glyph = '', hl = 'MiniIconsRed' },
          ['package-lock.json'] = { glyph = '', hl = 'MiniIconsRed' },
          ['.git-blame-ignore-revs'] = { glyph = '󰊢', hl = 'MiniIconsOrange' },
          ['lazy-lock.json'] = { glyph = '󰒲', hl = 'MiniIconsBlue' },
          config = { glyph = '󰒓', hl = 'MiniIconsCyan' },
          ['Cargo.lock'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['Cargo.toml'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['rustfmt.toml'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['rust-toolchain.toml'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['tmux.conf'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['.tmux.conf'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['webpack.config.ts'] = { glyph = '', hl = 'MiniIconsBlue' },
          ['webpack.config.js'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['.eslintrc.js'] = { glyph = '󰱺', hl = 'MiniIconsPurple' },
          ['stylelint.config.js'] = { glyph = '', hl = 'MiniIconsGrey' },
          ['.terraform-version'] = { glyph = '󱁢', hl = 'MiniIconsCyan' },
          ['init.lua'] = { glyph = '󰢱', hl = 'MiniIconsAzure' },
          ['nvim.version'] = { glyph = '', hl = 'MiniIconsGreen' },
        },
        extension = {
          bin = { glyph = '', hl = 'MiniIconsGrey' },
          h = { glyph = '󰙲', hl = 'MiniIconsPurple' },
          fish = { glyph = '󰈺', hl = 'MiniIconsOrange' },
          bash = { glyph = '', hl = 'MiniIconsGrey' },
          sh = { glyph = '', hl = 'MiniIconsGrey' },
          rc = { glyph = '󰒓', hl = 'MiniIconsCyan' },
          ttf = { glyph = '', hl = 'MiniIconsGrey' },
          otf = { glyph = '', hl = 'MiniIconsGrey' },
          swcrc = { glyph = '', hl = 'MiniIconsYellow' },
          js = { glyph = '', hl = 'MiniIconsOrange' },
          cjs = { glyph = '', hl = 'MiniIconsOrange' },
          mjs = { glyph = '', hl = 'MiniIconsOrange' },
          ts = { glyph = '', hl = 'MiniIconsBlue' },
          mts = { glyph = '', hl = 'MiniIconsBlue' },
          cts = { glyph = '', hl = 'MiniIconsBlue' },
          ['d.ts'] = { glyph = '', hl = 'MiniIconsOrange' },
          ['test.ts'] = { glyph = '', hl = 'MiniIconsCyan' },
          ['test.tsx'] = { glyph = '', hl = 'MiniIconsCyan' },
        },
        directory = {
          ['.vscode'] = { glyph = '', hl = 'MiniIconsBlue' },
          ['.github'] = { glyph = '', hl = 'MiniIconsGrey' },
          ['bazel-out'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['bazel-testlogs'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['bazel-bin'] = { glyph = '', hl = 'MiniIconsGreen' },
          ['.cargo'] = { glyph = '', hl = 'MiniIconsOrange' },
        },
      })
      require('mini.icons').mock_nvim_web_devicons()
    end,
  },

  {
    -- Set lualine as statusline
    'nvim-lualine/lualine.nvim',
    lazy = false,
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
      vim.api.nvim_set_hl(0, 'TreesitterContext', { link = 'Normal' })
      vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { link = 'LineNr' })
      require('treesitter-context').setup({
        mode = 'topline',
        line_numbers = true,
        max_lines = 10,
        separator = '─',
        ---@param bufnr number
        on_attach = function(bufnr)
          -- Disable at 512KB
          return not is_buf_large(bufnr, 1024 * 512)
        end,
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
      require('leap.user').add_default_mappings()
      require('leap.opts').default.substitute_chars = { ['{'] = 'b', ['}'] = 'b', ['('] = 'p', [')'] = 'p', ['['] = 'b', [']'] = 'b' }
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
            sign = { namespace = { 'diagnostic/signs' }, colwidth = 2 },
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

  -- Sudo write and read without executing nvim as root.
  {
    'lambdalisue/vim-suda',
    cmd = { 'SudaRead', 'SudaWrite' },
  },

  {
    'nvim-pack/nvim-spectre',
    cmd = { 'Spectre' },
    config = function()
      require('spectre').setup({
        use_trouble_qf = true,
        mapping = {
          ['send_to_qf'] = {
            map = '<leader>x',
            cmd = "<cmd>lua require('spectre.actions').send_to_qf()<CR>",
            desc = 'send all items to quickfix',
          },
        },
        highlight = {
          ui = 'String',
          search = 'DiffAdd',
          replace = 'DiffDelete',
        },
      })
    end,
  },

  -- Take screenshots of highlighted text.
  {
    'michaelrommel/nvim-silicon',
    lazy = true,
    config = function()
      require('silicon').setup({
        debug = true,
        disable_defaults = true,
        font = 'MonaspiceKr Nerd Font',
        theme = 'Monokai Extended',
      })
    end,
  },

  -- Faster LuaLS completions
  {
    'folke/lazydev.nvim',
    ft = 'lua', -- only load on lua files
    config = function()
      require('lazydev').setup({
        library = {
          'lazy.nvim',
          { path = 'luvit-meta/library', words = { 'vim%.uv' } },
        },
      })
    end,
  },

  --- Optional types for vim.uv
  { 'Bilal2453/luvit-meta', lazy = true },

  -- Adds additional extensions for clangd.
  {
    'p00f/clangd_extensions.nvim',
    cond = function()
      return require('utils.config').USE_CLANGD
    end,
    config = function()
      require('clangd_extensions').setup({
        ast = {
          role_icons = {
            type = '',
            declaration = '',
            expression = '',
            specifier = '',
            statement = '',
            ['template argument'] = '',
          },
          kind_icons = {
            Compound = '',
            Recovery = '',
            TranslationUnit = '',
            PackExpansion = '',
            TemplateTypeParm = '',
            TemplateTemplateParm = '',
            TemplateParamObject = '',
          },
        },
      })
    end,
  },

  -- Automatically install LSPs to stdpath for neovim
  { 'williamboman/mason.nvim', config = true, cmd = { 'Mason' } },

  -- Easily surround characters
  {
    'kylechui/nvim-surround',
    event = 'VeryLazy',
    config = function()
      require('nvim-surround').setup({})
    end,
  },

  -- Better rust tools
  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
  },

  -- Support textDocument/documentLink
  {
    'icholy/lsplinks.nvim',
    lazy = true,
    config = function()
      vim.api.nvim_set_hl(0, 'LspLink', { underdotted = true })
      require('lsplinks').setup({
        highlight = true,
        hl_group = 'LspLink',
      })
    end,
  },

  -- XCode features in neovim
  {
    'wojciech-kulik/xcodebuild.nvim',
    ft = { 'swift' },
    config = function()
      require('xcodebuild').setup({})
    end,
  },
}
