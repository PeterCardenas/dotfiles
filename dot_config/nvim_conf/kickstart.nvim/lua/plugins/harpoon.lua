-- Keymap
vim.keymap.set('n', '<leader>ma',
  function()
    require('harpoon.mark').add_file()
    require('harpoon.mark').store_offset()
  end,
  { desc = "Add file to harpoon" }
)
vim.keymap.set('n', '<leader>fm',
  function()
    require('telescope').extensions.harpoon.marks(
      require('telescope.themes').get_dropdown({
        winblend = 10,
        previewer = true,
      })
    )
  end,
  { desc = "Toggle harpoon menu" }
)
local function create_harpoon_keymap(mark_no)
  vim.keymap.set('n', string.format('<leader>%d', mark_no),
    function()
      require('harpoon.ui').nav_file(mark_no)
    end,
    { desc = string.format("Go to harpoon mark %d", mark_no) }
  )
  vim.keymap.set('n', string.format('<leader>m%d', mark_no),
    function()
      require('harpoon.mark').set_current_at(mark_no)
    end,
    { desc = string.format("Set current file to mark %d", mark_no) }
  )
end
for mark_no = 1, 4 do create_harpoon_keymap(mark_no) end

---@type LazyPluginSpec
return {
  'ThePrimeagen/harpoon',
  lazy = true,
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require("telescope").load_extension('harpoon')
  end,
}
