---@param key string
---@param action fun(): nil
local function keymap(key, action)
  vim.keymap.set({ 'n', 'v' }, key, action, { noremap = true, silent = true })
end

keymap('<C-u>', function()
  require('neoscroll').new_scroll(-vim.wo.scroll, { duration = 150, easing = 'sine', move_cursor = true })
end)

keymap('<C-d>', function()
  require('neoscroll').new_scroll(vim.wo.scroll, { move_cursor = true, duration = 150, easing = 'sine' })
end)

keymap('<C-y>', function()
  require('neoscroll').new_scroll(-0.10, { move_cursor = false, duration = 75, easing = '' })
end)

keymap('<C-e>', function()
  require('neoscroll').new_scroll(0.10, { move_cursor = false, duration = 75, easing = '' })
end)

keymap('zt', function()
  require('neoscroll').zt({ half_win_duration = 75, easing = 'sine' })
end)

keymap('zz', function()
  require('neoscroll').zz({ half_win_duration = 75, easing = 'sine' })
end)

keymap('zb', function()
  require('neoscroll').zb({ half_win_duration = 75, easing = 'sine' })
end)

-- TODO: Properly gg and G, currently this is way too slow.
-- Reference: https://github.com/karb94/neoscroll.nvim/issues/23
-- keymap('gg', function()
--   local winid = vim.api.nvim_get_current_win()
--   local bufnr = vim.api.nvim_win_get_buf(winid)
--   require('neoscroll').scroll(-2 * vim.api.nvim_buf_line_count(0), true, 150, 'sine', { kind = 'gg', winid = winid, bufnr = bufnr }, winid)
-- end)

-- keymap('G', function()
--   local winid = vim.api.nvim_get_current_win()
--   local bufnr = vim.api.nvim_win_get_buf(winid)
--   require('neoscroll').scroll(2 * vim.api.nvim_buf_line_count(0), true, 150, 'sine', { kind = 'G', winid = winid, bufnr = bufnr }, winid)
-- end)

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
        post_hook = function(info)
          if info == nil then
            return
          end
          if info.kind == 'gg' then
            vim.api.nvim_win_set_cursor(info.winid, { 1, 0 })
          elseif info.kind == 'G' then
            local line = vim.api.nvim_buf_line_count(info.bufnr)
            vim.api.nvim_win_set_cursor(info.winid, { line, 0 })
          end
        end,
      })
    end,
  },
}
