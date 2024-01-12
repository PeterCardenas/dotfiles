local M = {}

-- TODO(@PeterCardenas): Figure out how to use variables for these colors.
-- link currently does not work.

function M.set_focused_colors()
  vim.cmd([[highlight Normal guibg=#24283b]])
  vim.cmd([[highlight NormalSB guibg=#24283b]])
  vim.cmd([[highlight NormalNC guibg=#24283b]])
  vim.cmd([[highlight NormalFloat guibg=#24283b]])
  vim.cmd([[highlight FoldColumn guibg=#24283b]])
  vim.cmd([[highlight SignColumn guibg=#24283b]])
  vim.cmd([[highlight CursorLine guibg=#2a2e40]])
end

function M.set_unfocused_colors()
  vim.cmd([[highlight Normal guibg=#1f2335]])
  vim.cmd([[highlight NormalSB guibg=#1f2335]])
  vim.cmd([[highlight NormalNC guibg=#1f2335]])
  vim.cmd([[highlight NormalFloat guibg=#1f2335]])
  vim.cmd([[highlight FoldColumn guibg=#1f2335]])
  vim.cmd([[highlight SignColumn guibg=#1f2335]])
  vim.cmd([[highlight CursorLine guibg=#1f2335]])
end

return M
