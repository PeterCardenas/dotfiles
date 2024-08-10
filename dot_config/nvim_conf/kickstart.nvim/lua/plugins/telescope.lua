local nmap = require('utils.keymap').nmap

-- Telescope keymaps
nmap('[F]ind [O]ld files', 'fo', function()
  require('telescope.builtin').oldfiles()
end)

nmap('[/] Fuzzily search in current buffer', '/', function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({
    winblend = 10,
    previewer = true,
    layout_config = {
      width = 0.8,
    },
  }))
end)

nmap('[F]ind b[u]ffers', 'fu', function()
  require('telescope.builtin').buffers({
    ignore_current_buffer = true,
    sort_mru = true,
  })
end)

nmap('[F]ind [F]iles', 'ff', function()
  require('telescope.builtin').find_files({ hidden = true })
end)

nmap('[F]ind Any [F]ile', 'fF', function()
  require('telescope.builtin').find_files({ hidden = true, no_ignore = true })
end)

nmap('[F]ind [W]ords with ripgrep', 'fw', function()
  require('telescope').extensions.live_grep_args.live_grep_args()
end)

nmap('[F]ind [W]ords with ripgrep across all files', 'fW', function()
  require('telescope.builtin').live_grep({
    additional_args = function(args)
      return vim.list_extend(args, { '--hidden', '--no-ignore' })
    end,
  })
end)

nmap('[F]ind [H]elp', 'fh', function()
  require('telescope.builtin').help_tags()
end)

nmap('[L]anguage [D]iagnostic', 'ld', function()
  require('trouble').open('document_diagnostics')
end)

nmap('[L]ist [D]iagnostics', 'lD', function()
  require('trouble').open('workspace_diagnostics')
end)

nmap('[F]ind [R]resume', 'fr', function()
  require('telescope.builtin').resume()
end)

nmap('[F]ind [N]otification', 'fn', function()
  require('telescope').extensions.notify.notify()
end)

---@type LazyPluginSpec
return {
  -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  branch = '0.1.x',
  lazy = true,
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
