local M = {}

function M.set_focused_colors()
  local background = '#24283b'
  vim.api.nvim_set_hl(0, 'Normal', { background = background })
  vim.api.nvim_set_hl(0, 'NormalSB', { background = background })
  vim.api.nvim_set_hl(0, 'NormalNC', { background = background })
  vim.api.nvim_set_hl(0, 'NormalFloat', { background = background })
  vim.api.nvim_set_hl(0, 'CursorLine', { background = '#2a2e40' })
  vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { foreground = '#3b4261', background = background })
end

function M.set_unfocused_colors()
  local background = '#1f2335'
  vim.api.nvim_set_hl(0, 'Normal', { background = background })
  vim.api.nvim_set_hl(0, 'NormalSB', { background = background })
  vim.api.nvim_set_hl(0, 'NormalNC', { background = background })
  vim.api.nvim_set_hl(0, 'NormalFloat', { background = background })
  vim.api.nvim_set_hl(0, 'CursorLine', { background = background })
  vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { foreground = '#3b4261', background = background })
end

return M
