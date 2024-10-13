require('plugins.telescope.setup').create_keymaps()

---@type LazyPluginSpec[]
return {
  {
    'ibhagwan/fzf-lua',
    dependencies = {
      'echasnovski/mini.icons',
    },
    cmd = { 'FzfLua' },
    config = function()
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
        files = {
          git_icons = false,
        },
        grep = {
          git_icons = false,
        },
      })
    end,
  },
}
