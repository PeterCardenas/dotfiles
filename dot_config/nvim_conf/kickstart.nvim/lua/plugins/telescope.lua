-- Telescope keymaps
vim.keymap.set('n', '<leader>fo', function()
  require('telescope.builtin').oldfiles()
end, { desc = '[F]ind [O]ld files' })
vim.keymap.set('n', '<leader>/', function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({
    winblend = 10,
    previewer = true,
    layout_config = {
      width = 0.8,
    },
  }))
end, { desc = '[/] Fuzzily search in current buffer' })
vim.keymap.set('n', '<leader>ff', function()
  require('telescope.builtin').find_files()
end, { desc = '[F]ind [F]iles' })
vim.keymap.set('n', '<leader>fF', function()
  require('telescope.builtin').find_files({ hidden = true, no_ignore = true })
end, { desc = '[F]ind Any [F]ile' })
vim.keymap.set('n', '<leader>fw', function()
  require('telescope').extensions.live_grep_args.live_grep_args()
end, { desc = '[F]ind [W]ords with ripgrep' })
vim.keymap.set('n', '<leader>fW', function()
  require('telescope.builtin').live_grep({
    additional_args = function(args)
      return vim.list_extend(args, { '--hidden', '--no-ignore' })
    end,
  })
end, { desc = '[F]ind [W]ords with ripgrep across all files' })
vim.keymap.set('n', '<leader>fh', function()
  require('telescope.builtin').help_tags()
end, { desc = '[F]ind [H]elp' })
vim.keymap.set('n', '<leader>ld', function()
  require('trouble').open('document_diagnostics')
end, { desc = '[L]anguage [D]iagnostic' })
vim.keymap.set('n', '<leader>fr', function()
  require('telescope.builtin').resume()
end, { desc = '[F]ind [R]resume' })
vim.keymap.set('n', '<leader>fn', function()
  require('telescope').extensions.notify.notify()
end, { desc = '[F]ind [N]otification' })

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
        prompt_prefix = '  ',
        selection_caret = '❯ ',
        mappings = {
          i = {
            ['<C-u>'] = false,
            ['<C-d>'] = false,
            ['<C-n>'] = telescope_actions.cycle_history_next,
            ['<C-p>'] = telescope_actions.cycle_history_prev,
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
    pcall(require('telescope').load_extension, 'fzf')
  end,
}
