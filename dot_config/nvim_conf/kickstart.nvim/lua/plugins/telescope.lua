---@type LazyPluginSpec
return {
  -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  cmd = { 'Telescope' },
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    -- Fuzzy Finder Algorithm which requires local dependencies to be built.
    -- Only load if `make` is available. Make sure you have the system
    -- requirements installed.
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable('make') == 1
      end,
    },
  },
  config = function()
    -- [[ Configure Telescope ]]
    local telescope_actions = require('telescope.actions')
    local lga_actions = require('telescope-live-grep-args.actions')
    require('telescope').setup({
      defaults = {
        layout_config = {
          horizontal = {
            prompt_position = 'top',
            width = 0.98,
          },
          vertical = {
            width = 0.98,
          },
        },
        sorting_strategy = 'ascending',
        prompt_prefix = ' ',
        selection_caret = '❯ ',
        mappings = {
          i = {
            ['<C-j>'] = telescope_actions.move_selection_next,
            ['<C-k>'] = telescope_actions.move_selection_previous,
          },
          n = { ['q'] = telescope_actions.close },
        },
      },
      extensions = {
        live_grep_args = {
          mappings = { -- extend mappings
            i = {
              ['<C-s>'] = lga_actions.quote_prompt({ postfix = ' -Ttest' }),
            },
          },
        },
      },
    })

    -- Enable telescope fzf native, if installed
    require('telescope').load_extension('fzf')
  end,
}
