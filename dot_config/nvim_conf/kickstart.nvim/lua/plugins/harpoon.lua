local nmap = require('utils.keymap').nmap

-- Keymap
nmap('Add file to harpoon', 'ma', function()
  require('harpoon.mark').add_file()
  require('harpoon.mark').store_offset()
end)
nmap('Toggle harpoon menu', 'fm', function()
  require('telescope').extensions.harpoon.marks(require('telescope.themes').get_dropdown({
    winblend = 10,
    previewer = true,
  }))
end)
---@param mark_no number
local function create_harpoon_keymap(mark_no)
  local mark_no_str = tostring(mark_no)
  nmap('Go to harpoon mark ' .. mark_no_str, mark_no_str, function()
    require('harpoon.ui').nav_file(mark_no)
  end)
  nmap('Set current file to mark ' .. mark_no_str, 'm' .. mark_no_str, function()
    require('harpoon.mark').set_current_at(mark_no)
  end)
end
for mark_no = 1, 4 do
  create_harpoon_keymap(mark_no)
end

---@type LazyPluginSpec
return {
  'ThePrimeagen/harpoon',
  lazy = true,
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('telescope').load_extension('harpoon')
  end,
}
