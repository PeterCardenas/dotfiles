-- Telescope keymaps
vim.keymap.set('n', '<leader>fo',
  function()
    require('telescope.builtin').oldfiles()
  end,
  { desc = '[?] Find recently opened files' }
)
vim.keymap.set('n', '<leader>/',
  function()
    -- You can pass additional configuration to telescope to change theme, layout, etc.
    require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
      winblend = 10,
      previewer = true,
    })
  end,
  { desc = '[/] Fuzzily search in current buffer' }
)
vim.keymap.set('n', '<leader>ff',
  function()
    require('telescope.builtin').find_files()
  end,
  { desc = '[F]ind [F]iles' }
)
vim.keymap.set('n', '<leader>fw',
  function()
    require('telescope').extensions.live_grep_args.live_grep_args()
  end,
  { desc = '[F]ind [W]ords with ripgrep' }
)
vim.keymap.set('n', '<leader>sh',
  function()
    require('telescope.builtin').help_tags()
  end,
  { desc = '[S]earch [H]elp' }
)
vim.keymap.set('n', '<leader>ld',
  function()
    require('telescope.builtin').diagnostics({ bufnr = 0 })
  end,
  { desc = '[L]anguage [D]iagnostics for current buffer' }
)
vim.keymap.set('n', '<leader>sr',
  function()
    require('telescope.builtin').resume()
  end,
  { desc = '[S]earch [R]resume' }
)

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
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
  },
  config = function()
    -- [[ Configure Telescope ]]
    local telescope_actions = require "telescope.actions"
    local lga_actions = require "telescope-live-grep-args.actions"
    require('telescope').setup {
      defaults = {
        layout_config = {
          horizontal = {
            prompt_position = "top",
          }
        },
        sorting_strategy = "ascending",
        path_display = { "truncate" },
        prompt_prefix = "  ",
        selection_caret = "❯ ",
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
              ["<C-s>"] = lga_actions.quote_prompt({ postfix = " -Ttest " }),
            },
          },
        }
      }
    }

    -- Enable telescope fzf native, if installed
    pcall(require('telescope').load_extension, 'fzf')
  end
}
