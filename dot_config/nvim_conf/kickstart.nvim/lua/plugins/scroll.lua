---@param key string
---@param action fun(): nil
local function keymap(key, action)
  vim.keymap.set({ 'n', 'v' }, key, action, { noremap = true, silent = true })
end

keymap('<C-u>', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').scroll(-vim.wo.scroll, true, 150, 'sine', {}, winid)
end)

keymap('<C-d>', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').scroll(vim.wo.scroll, true, 150, 'sine', {}, winid)
end)

keymap('<C-y>', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').scroll(-0.10, false, 75, '', {}, winid)
end)

keymap('<C-e>', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').scroll(0.10, false, 75, '', {}, winid)
end)

keymap('zt', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').zt(75, 'sine', {}, winid)
end)

keymap('zz', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').zz(75, 'sine', {}, winid)
end)

keymap('zb', function()
  local winid = vim.api.nvim_get_current_win()
  require('neoscroll').zb(75, 'sine', {}, winid)
end)

---@type LazyPluginSpec[]
return {
  -- Smooth scrolling
  {
    'karb94/neoscroll.nvim',
    lazy = true,
    config = function()
      require('neoscroll').setup({
        cursor_scrolls_alone = false,
        stop_eof = false,
      })
    end,
  },
}
