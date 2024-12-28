require('plugins.telescope.setup').create_keymaps()

---@type LazyPluginSpec[]
return {
  {
    'ibhagwan/fzf-lua',
    dependencies = {
      'echasnovski/mini.icons',
      'nvim-treesitter/nvim-treesitter',
    },
    cmd = { 'FzfLua' },
    config = function()
      -- Clear fuzzy toggle for grep
      require('fzf-lua.defaults').defaults.grep.actions = {}
      require('fzf-lua').setup({
        keymap = {
          builtin = {
            ['<C-D>'] = 'preview-page-down',
            ['<C-U>'] = 'preview-page-up',
          },
        },
        winopts = {
          height = 0.98,
          width = 0.98,
        },
        previewers = {
          builtin = {
            treesitter = {
              context = false,
            },
          },
        },
        files = {
          git_icons = false,
          -- TODO: Make this hide ignored files by default once this can be toggled.
          cmd = require('plugins.telescope.setup').rg_files_cmd(true),
        },
        grep = {
          git_icons = false,
          -- TODO: Make this hide ignored files by default once this can be toggled.
          cmd = require('plugins.telescope.setup').rg_words_cmd(true),
          multiprocess = true,
          multiline = 1,
        },
        oldfiles = {
          include_current_session = true,
        },
      })
    end,
  },
}
