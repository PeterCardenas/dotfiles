-- Install package manager
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- Add plugins for lazy.nvim.
require('lazy').setup({
  -- Git related plugins
  'tpope/vim-fugitive',
  'tpope/vim-rhubarb',

  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- Plugin configs that are of decent heft.
  require('plugins.heirline'),
  require('plugins.lsp'),
  require('plugins.cmp'),
  require('plugins.telescope'),
  require('plugins.treesitter'),
  require('plugins.gitsigns'),
  require('plugins.tmux'),
  require('plugins.neo_tree'),
  require('plugins.debug'),
  require('plugins.harpoon'),
  require('plugins.dashboard'),
  require('plugins.breadcrumbs'),

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
            accept = "<C-c>",
          },
        },
      })
    end
  },

  -- Useful plugin to show you pending keybinds.
  {
    'folke/which-key.nvim',
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    config = function()
      require('which-key').setup({
        disable = {
          filetypes = { "TelescopePrompt" }
        },
      })
    end
  },

  -- Better UI for select, notifications, popups, and many others.
  {
    "folke/noice.nvim",
    priority = 999,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    config = function()
      require("noice").setup({
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = true,         -- use a classic bottom cmdline for search
          command_palette = true,       -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = false,           -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = false,       -- add a border to hover docs and signature help
        },
      })
    end
  },

  -- Better code action menu
  {
    "weilbith/nvim-code-action-menu"
  },

  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd('colorscheme tokyonight-storm')
    end,
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
                error = ' ',
                warn = ' ',
                info = ' ',
                hint = ' ',
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
    event = { "BufReadPre", "BufNewFile" }
  },

  -- Camel-case and snake-case motion
  { "bkad/CamelCaseMotion", event = { "BufReadPre", "BufNewFile" } },

  -- Sticky scroll
  {
    "nvim-treesitter/nvim-treesitter-context",
    after = "nvim-treesitter",
    config = function()
      require("treesitter-context").setup({
        mode = "topline",
        line_numbers = true,
        on_attach = function (bufnr)
          return vim.bo[bufnr].ft ~= "python"
        end
      })
    end,
  },

  -- Ripgrep with file name filtering
  {
    "nvim-telescope/telescope-live-grep-args.nvim",
    after = "telescope.nvim",
    config = function() require("telescope").load_extension "live_grep_args" end,
  },

  -- Easy folding
  {
    "kevinhwang91/nvim-ufo",
    dependencies = {
      "kevinhwang91/promise-async",
    },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require("ufo").setup({
        provider_selector = function() return { "treesitter", "indent" } end,
      })
    end,
  },

  -- Fast motion commands
  {
    "ggandor/lightspeed.nvim",
    requires = { "tpope/vim-repeat" },
    event = { "BufReadPre", "BufNewFile" },
  },

  -- Status column
  {
    "luukvbaal/statuscol.nvim",
    config = function()
      local builtin = require "statuscol.builtin"

      require("statuscol").setup({
        foldfunc = 'builtin',
        ft_ignore = { "dashboard", "neo-tree", "help" },
        segments = {
          { text = { builtin.foldfunc }, click = "v:lua.ScFa" },
          {
            sign = { name = { "Diagnostic" }, colwidth = 2 },
            click = "v:lua.ScSa",
          },
          { text = { builtin.lnumfunc }, click = "v:lua.ScLa", },
          {
            sign = { namespace = { "gitsigns" }, maxwidth = 2, colwidth = 1, wrap = true },
            click = "v:lua.ScSa"
          },
        },
      })
    end,
  },

  -- Add Pairs Automatically
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require('nvim-autopairs').setup({
        check_ts = true,
      })
    end
  },

  -- Persists sessions based on directory.
  {
    "Shatur/neovim-session-manager",
    event = "BufWritePost",
    config = function()
      require "session_manager".setup({
        autoload_mode = require("session_manager.config").AutoloadMode.CurrentDir,
        autosave_ignore_dirs = { "~/", "~/Downloads", "/" },
      })
    end,
  },

  -- Add lazygit neovim integration.
  {
    "kdheepak/lazygit.nvim",
    -- optional for floating window border decoration
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
  }
}, {
  change_detection = {
    enabled = true,
    notify = true,
  },
})
