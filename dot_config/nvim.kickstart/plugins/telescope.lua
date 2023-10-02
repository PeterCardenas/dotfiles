---@type LazyPluginSpec
return {
  -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  branch = '0.1.x',
  dependencies = {
    'nvim-lua/plenary.nvim',
    -- Fuzzy Finder Algorithm which requires local dependencies to be built.
    -- Only load if `make` is available. Make sure you have the system
    -- requirements installed.
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      -- NOTE: If you are having trouble with this installation,
      --       refer to the README for telescope-fzf-native for more instructions.
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
  },
  config = function()
    -- [[ Configure Telescope ]]
    -- See `:help telescope` and `:help telescope.setup()`
    local telescope_actions = require "telescope.actions"
    local lga_actions = require "telescope-live-grep-args.actions"
    require('telescope').setup {
      defaults = {
        mappings = {
          i = {
            ['<C-u>'] = false,
            ['<C-d>'] = false,
            ['<C-n>'] = telescope_actions.cycle_history_next,
            ['<C-p>'] = telescope_actions.cycle_history_prev,
            ['<C-j>'] = telescope_actions.move_selection_next,
            ['<C-k>'] = telescope_actions.move_selection_previous,
          },
          n = { ["q"] = telescope_actions.close },
        },
      },
      extensions = {
        live_grep_args = {
          mappings = { -- extend mappings
            i = {
              ["<C-k>"] = lga_actions.quote_prompt({ postfix = " -Ttest " }),
            },
          },
        }
      }
    }

    -- Enable telescope fzf native, if installed
    pcall(require('telescope').load_extension, 'fzf')
  end
}
