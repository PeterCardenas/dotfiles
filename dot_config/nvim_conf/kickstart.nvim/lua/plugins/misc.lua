local Async = require('utils.async')
local Buf = require('utils.buf')
local Config = require('utils.config')
local Git = require('utils.git')

local large_file_group = vim.api.nvim_create_augroup('Disable Large File Plugins', { clear = true })
vim.api.nvim_create_autocmd('BufReadPre', {
  desc = 'Conditionally load plugins for large files',
  group = large_file_group,
  callback = function(args)
    --Disables at 512KB
    local should_disable = Buf.is_buf_large(args.buf, 1024 * 512)
    require('ibl').setup_buffer(args.buf, {
      enabled = not should_disable,
    })
  end,
})

-- TODO: sync ordering of buffers to session
-- local sync_buffers_group = vim.api.nvim_create_augroup('Sync Buffers to Session', { clear = true })
-- vim.api.nvim_create_autocmd('SessionLoadPost', {
--   group = sync_buffers_group,
--   callback = function()
--     if not vim.g.session_buffers then
--       return
--     end
--     local bufs_with_names = vim.json.decode(vim.g.session_buffers)
--     for _, buf_with_name in ipairs(bufs_with_names) do
--       local bufnr = buf_with_name.bufnr
--       local name = buf_with_name.name
--       vim.cmd.badd({ args = { '+' .. bufnr, name } })
--     end
--     if #bufs_with_names > 0 then
--       vim.cmd.edit({ args = { bufs_with_names[#bufs_with_names].name } })
--       if #bufs_with_names > 1 then
--         vim.cmd.balt({ args = { bufs_with_names[#bufs_with_names - 1].name } })
--       end
--     end
--   end,
-- })
--
vim.api.nvim_create_user_command('SiliconCopy', function()
  require('silicon').clip()
end, { nargs = 0, range = true })

vim.api.nvim_create_user_command('DiffviewPR', function()
  Async.void(
    ---@async
    function()
      local success, default_branch = Git.get_default_branch()
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

local nmap = require('utils.keymap').nmap
nmap('Resume trouble', 'tr', function()
  local last_mode = require('trouble').last_mode
  require('trouble').open({ mode = last_mode })
end)

nmap('[L]anguage [D]iagnostic', 'ld', function()
  require('trouble').open({ mode = 'diagnostics', auto_jump = false })
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
      return false
    end,
    config = function()
      require('copilot').setup({
        suggestion = {
          auto_trigger = true,
          keymap = {
            accept = '<C-Y>',
            accept_word = '<C-S-Y>',
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
      return Config.USE_SUPERMAVEN
    end,
    config = function()
      require('supermaven-nvim').setup({
        keymaps = {
          accept_suggestion = '<C-Y>',
          accept_word = '<C-S-Y>',
        },
        log_level = 'warn',
      })
      -- Assumes the next buffer created will be the SuperMaven activation popup.
      vim.api.nvim_create_autocmd('BufNew', {
        once = true,
        callback = function()
          require('supermaven-nvim.binary.binary_handler'):close_popup()
        end,
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
      ---@diagnostic disable-next-line: missing-fields
      require('which-key').setup({
        disable = {
          filetypes = { 'TelescopePrompt' },
        },
      })
      require('which-key').add({
        { '<leader>a', group = 'Avante AI' },
        { '<leader>f', group = 'Find' },
        { '<leader>d', group = 'Debug' },
        { '<leader>g', group = 'Git' },
        { '<leader>l', group = 'LSP' },
        { '<leader>t', group = 'Trouble' },
        { '<leader>S', group = 'Session' },
        { '<leader>o', group = 'File Explorer' },
        { '<leader>m', group = 'Harpoon' },
        { '<leader>u', group = 'Settings' },
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
      ---@diagnostic disable-next-line: missing-fields
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
          -- HACK: ignore this false positive notifications from octo.nvim
          -- TODO: Investigate why this notifications is popping up
          {
            filter = {
              event = 'notify',
              any = {
                { find = 'You are not logged into any accounts on' },
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
          javascript = { glyph = '', hl = 'MiniIconsOrange' },
          ['markdown.mdx'] = { glyph = '󰍔', hl = 'MiniIconsGrey' },
          fish = { glyph = '󰈺', hl = 'MiniIconsOrange' },
          bash = { glyph = '', hl = 'MiniIconsGrey' },
          sh = { glyph = '', hl = 'MiniIconsGrey' },
          spectre_panel = { glyph = '', hl = 'MiniIconsOrange' },
          ghostty = { glyph = '󰒓', hl = 'MiniIconsCyan' },
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
          ['tsconfig.base.json'] = { glyph = '', hl = 'MiniIconsBlue' },
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
          ['gpg-agent.conf'] = { glyph = '', hl = 'MiniIconsYellow' },
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
          ['template.yaml'] = { glyph = '', hl = 'MiniIconsGrey' },
          mdx = { glyph = '󰍔', hl = 'MiniIconsGrey' },
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
                ---@type boolean
                local has_status = require('noice').api.status.mode.has()
                if not has_status then
                  return false
                end
                ---@type string
                local status = require('noice').api.status.mode.get()
                return vim.startswith(status, 'recording')
              end,
              color = { fg = '#ff9e64' },
            },
            -- TODO: Move this to the tmux statusbar
            {
              function()
                return 'SSH'
              end,
              icon = { '󰌘', color = { fg = '#ff9e64' } },
              cond = function()
                return vim.env.SSH_CONNECTION ~= nil
              end,
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
        provider_selector = function(bufnr)
          local filename = vim.api.nvim_buf_get_name(bufnr)
          if vim.endswith(filename, 'template.yaml') then
            return { 'indent' }
          end
          return { 'treesitter', 'indent' }
        end,
      })
    end,
  },

  -- Fast motion commands
  {
    'ggandor/leap.nvim',
    dependencies = { 'tpope/vim-repeat' },
    event = { 'BufReadPre', 'BufNewFile', 'BufEnter' },
    config = function()
      -- TODO: Remove ds, cs, and ys keymaps
      vim.keymap.set({ 'n', 'v', 'x', 'o' }, 's', '<Plug>(leap-forward)')
      -- TODO: Jumping backwards does not work in visual mode.
      vim.keymap.set({ 'n', 'v', 'x', 'o' }, 'S', '<Plug>(leap-backward)')
      vim.keymap.set({ 'n', 'v', 'x', 'o' }, 'gs', '<Plug>(leap-from-window)')
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
            sign = { namespace = { 'diagnostic/signs' }, colwidth = 1 },
            click = 'v:lua.ScSa',
          },
          { text = { builtin.lnumfunc }, click = 'v:lua.ScLa' },
          -- Debugger icons
          {
            sign = { name = { '.*' }, colwidth = 1 },
            auto = true,
            click = 'v:lua.ScSa',
          },
          {
            sign = { namespace = { 'gitsigns' }, colwidth = 1 },
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
        autosave_ignore_buftypes = { 'terminal', 'help', 'quickfix', 'prompt' },
      })
    end,
  },

  -- Profile lua neovim config.
  {
    'stevearc/profile.nvim',
    cond = function()
      return os.getenv('NVIM_PROFILE') ~= nil and not Config.USE_SNACKS_PROFILER
    end,
    priority = 100000,
    lazy = false,
    config = function()
      local profile_env = os.getenv('NVIM_PROFILE')
      if not profile_env then
        error('NVIM_PROFILE is not set')
        return
      end
      local function toggle_profile()
        local prof = require('profile')
        if prof.is_recording() then
          prof.stop()
          ---@diagnostic disable-next-line: missing-fields
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
      vim.api.nvim_create_user_command('ToggleProfile', toggle_profile, { nargs = 0 })
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

  -- Search/replace across multiple files
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

  -- Search/replace across multiple files (better than spectre?)
  {
    'MagicDuck/grug-far.nvim',
    cmd = { 'GrugFar' },
    config = function()
      require('grug-far').setup({
        openTargetWindow = {
          preferredLocation = 'right',
        },
        keymaps = {
          -- Allows for <leader>q for closing grug-far
          qflist = false,
        },
      })
      -- @diff.delta is not noticeable enough, but fixing it is not important.
      vim.api.nvim_set_hl(0, 'GrugFarResultsMatch', { link = 'CurSearch', force = true })
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
      -- TODO: Remove this hack once the following is merged: https://github.com/folke/lazydev.nvim/pull/96
      local supported_clients = { 'lua_ls', 'emmylua_ls' }
      ---@param client vim.lsp.Client
      local function emmylua_ls_supported(client)
        return client and vim.tbl_contains(supported_clients, client.name)
      end
      require('lazydev.lsp').supports = emmylua_ls_supported
      ---@diagnostic disable-next-line: missing-fields
      require('lazydev').setup({
        library = {
          'lazy.nvim',
          { path = 'luvit-meta/library', words = { 'vim%.uv', 'vim%.loop' } },
          { path = 'snacks.nvim', words = { 'Snacks' } },
        },
        enabled = function(root_dir)
          return not vim.uv.fs_stat(root_dir .. '/.luarc.json') or root_dir:find('%.local/share/nvim/lazy/')
        end,
      })
    end,
  },

  --- Optional types for vim.uv
  { 'Bilal2453/luvit-meta', lazy = true },

  -- Adds additional extensions for clangd.
  {
    'p00f/clangd_extensions.nvim',
    cond = function()
      return Config.USE_CLANGD
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
      -- TODO: Add delete surrounding if statement/function
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

  {
    'folke/zen-mode.nvim',
    cmd = { 'ZenMode' },
    config = function()
      require('zen-mode').setup()
    end,
  },

  -- Yank history
  {
    'gbprod/yanky.nvim',
    keys = {
      {
        '<leader>p',
        mode = { 'n', 'x' },
        function()
          require('telescope').extensions.yank_history.yank_history({})
        end,
        desc = 'Open Yank History',
      },
      { 'y', '<Plug>(YankyYank)', mode = { 'n', 'x' }, desc = 'Yank text' },
      { 'p', '<Plug>(YankyPutAfter)', mode = { 'n', 'x' }, desc = 'Put yanked text after cursor' },
      { 'P', '<Plug>(YankyPutBefore)', mode = { 'n', 'x' }, desc = 'Put yanked text before cursor' },
      { 'gp', '<Plug>(YankyGPutAfter)', mode = { 'n', 'x' }, desc = 'Put yanked text after selection' },
      { 'gP', '<Plug>(YankyGPutBefore)', mode = { 'n', 'x' }, desc = 'Put yanked text before selection' },
    },
    config = function()
      require('yanky').setup({
        -- TODO: would prefer sqlite but get some dynamic linking errors
        ring = {
          storage = 'shada',
          -- TODO: Cannot read from clipboard in tmux
          ignore_registers = { '_', '+', '*' },
        },
        system_clipboard = {
          sync_with_ring = false,
        },
        highlight = {
          timer = 150,
          on_yank = false,
          on_put = true,
        },
      })
    end,
  },

  {
    'folke/snacks.nvim',
    priority = 1009,
    lazy = false,
    config = function()
      -- ---@param key string
      -- ---@param action fun(): nil
      -- local function keymap(key, action)
      --   vim.keymap.set({ 'n', 'v' }, key, action, { noremap = true, silent = true })
      -- end
      -- ---@param fraction number
      -- local function get_lines_from_win_fraction(fraction)
      --   local winid = vim.api.nvim_get_current_win()
      --   local height_fraction = fraction * vim.api.nvim_win_get_height(winid)
      --   local lines
      --   if height_fraction < 0 then
      --     lines = -math.floor(math.abs(height_fraction) + 0.5)
      --   else
      --     lines = math.floor(height_fraction + 0.5)
      --   end
      --   if lines == 0 then
      --     return fraction < 0 and -1 or 1
      --   end
      --   return lines
      -- end
      -- keymap('<C-e>', function()
      --   local lines = get_lines_from_win_fraction(0.1)
      --   local ctrl_e = vim.api.nvim_replace_termcodes('<C-e>', false, false, true)
      --   vim.cmd.normal({ bang = true, args = { tostring(lines) .. ctrl_e } })
      -- end)
      -- keymap('<C-y>', function()
      --   local lines = get_lines_from_win_fraction(0.1)
      --   local ctrl_y = vim.api.nvim_replace_termcodes('<C-y>', false, false, true)
      --   vim.cmd('normal! ' .. tostring(lines) .. ctrl_y)
      -- end)
      vim.api.nvim_create_autocmd('User', {
        pattern = 'MiniFilesActionRename',
        callback = function(event)
          Snacks.rename.on_rename_file(event.data.from, event.data.to)
        end,
      })
      if Config.USE_SNACKS_PROFILER then
        vim.api.nvim_create_user_command('ToggleProfile', function()
          if Snacks.profiler.running() then
            Snacks.profiler.stop()
          else
            Snacks.profiler.start()
          end
        end, { nargs = 0 })
      end
      require('snacks').setup({
        -- TODO: Re-enable when indent is equal or better than indent-blankline
        -- indent = { enabled = true },
        -- TODO: Re-enable when scroll is equal or better than neoscroll
        -- scroll = { enabled = true },
        input = { enabled = true },
        quickfile = { enabled = true },
        words = { enabled = true },
        rename = { enabled = true },
        -- TODO: Enable when image is equal or better than image.nvim
        image = { enabled = false },
        -- TODO: Fully enable when trouble picker works
        profiler = { enabled = Config.USE_SNACKS_PROFILER },
        -- TODO: Re-enable when dashboard is equal or better than alpha.nvim
        -- dashboard = { enabled = true },
      })
    end,
  },
}
