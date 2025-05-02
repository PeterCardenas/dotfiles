local M = {}

---@param background string
---@param cursor_line string
local function set_colors(background, cursor_line)
  vim.api.nvim_set_hl(0, 'Normal', { background = background })
  vim.api.nvim_set_hl(0, 'NormalSB', { background = background })
  vim.api.nvim_set_hl(0, 'NormalNC', { background = background })
  vim.api.nvim_set_hl(0, 'NormalFloat', { background = background })
  local float_border_hl = vim.api.nvim_get_hl(0, { name = 'FloatBorder' })
  vim.api.nvim_set_hl(0, 'FloatBorder', { background = background, foreground = float_border_hl.fg })
  vim.api.nvim_set_hl(0, 'CursorLine', { background = cursor_line })
  vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { foreground = '#3b4261', background = background })
  local diagnostic_info_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticInfo' })
  vim.api.nvim_set_hl(0, 'NoiceConfirmBorder', { foreground = diagnostic_info_hl.fg, background = background })
  vim.api.nvim_set_hl(0, 'NoiceCmdlinePopupBorder', { foreground = diagnostic_info_hl.fg, background = background })
  local diagnostic_warn_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'NoiceCmdlinePopupBorderSearch', { foreground = diagnostic_warn_hl.fg, background = background })
  vim.api.nvim_set_hl(0, 'NoiceCmdlineIconSearch', { foreground = diagnostic_warn_hl.fg, background = background })
end

function M.set_focused_colors()
  local background = '#24283b'
  set_colors(background, '#2a2e40')
end

function M.set_unfocused_colors()
  local background = '#1f2335'
  set_colors(background, background)
end

return M
