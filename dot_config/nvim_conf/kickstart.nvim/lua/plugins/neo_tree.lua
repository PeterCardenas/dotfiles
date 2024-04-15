vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Open Neo-Tree on startup with directory',
  group = vim.api.nvim_create_augroup('neotree_start', { clear = true }),
  callback = function()
    local stats = vim.loop.fs_stat(vim.api.nvim_buf_get_name(0))
    if stats and stats.type == 'directory' then
      require('nvim-tree.actions.tree').open.fn()
    end
  end,
})

---@type LazyPluginSpec
return {
  -- File Explorer
  'nvim-tree/nvim-tree.lua',
  lazy = true,
  dependencies = {
    'nvim-tree/nvim-web-devicons',
  },
  config = function()
    require('nvim-tree').setup({
      update_focused_file = {
        enable = true,
      },
    })
  end,
}
