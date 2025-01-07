---@type LazyPluginSpec
return {
  'folke/tokyonight.nvim',
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight-storm')
    -- TODO: Change/remove this to something more unique when modules have semantic highlighting.
    vim.api.nvim_set_hl(0, '@module.python', { link = '@variable' })
    -- Make comments foreground brighter.
    vim.api.nvim_set_hl(0, 'Comment', { foreground = '#7c7c7c', italic = true, cterm = { italic = true } })
    -- More contrast for selected tab.
    vim.api.nvim_set_hl(0, 'TabLineSel', { foreground = '#e0e0e0', background = '#26355E' })
    -- Make tab title foreground brighter.
    vim.api.nvim_set_hl(0, 'TabLine', { foreground = '#7c7c7c', background = '#161F38' })
    -- Make git blame foreground brighter.
    vim.api.nvim_set_hl(0, 'GitSignsCurrentLineBlame', { foreground = '#7c7c7c' })
    -- Make leap backdrop foreground light grey (in case I forget the key to press lol).
    vim.api.nvim_set_hl(0, 'LeapBackdrop', { foreground = '#5C5C5C' })
    -- Add red close button highlight.
    vim.api.nvim_set_hl(0, 'TabLineClose', { foreground = '#DB4539' })
    -- Make unused variables brighter.
    vim.api.nvim_set_hl(0, 'DiagnosticUnnecessary', { foreground = '#7c7c7c' })
    -- Distinguish sign/fold/line column from background.
    ---@type vim.api.keyset.highlight
    local side_col_highlight = { foreground = '#454d71', background = '#292e42' }
    vim.api.nvim_set_hl(0, 'SignColumn', side_col_highlight)
    vim.api.nvim_set_hl(0, 'FoldColumn', side_col_highlight)
    vim.api.nvim_set_hl(0, 'LineNr', side_col_highlight)
    vim.api.nvim_set_hl(0, 'CursorLineNr', { foreground = '#ff9e64', bold = true, cterm = { bold = true }, background = side_col_highlight.background })
    local diagnostic_error_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticError' })
    vim.api.nvim_set_hl(0, 'DiagnosticSignError', { foreground = diagnostic_error_hl.fg, background = side_col_highlight.background })
    local diagnostic_warn_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticWarn' })
    vim.api.nvim_set_hl(0, 'DiagnosticSignWarn', { foreground = diagnostic_warn_hl.fg, background = side_col_highlight.background })
    local diagnostic_info_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticInfo' })
    vim.api.nvim_set_hl(0, 'DiagnosticSignInfo', { foreground = diagnostic_info_hl.fg, background = side_col_highlight.background })
    local diagnostic_hint_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticHint' })
    vim.api.nvim_set_hl(0, 'DiagnosticSignHint', { foreground = diagnostic_hint_hl.fg, background = side_col_highlight.background })
    -- Make git signs foreground brighter and make background same as status col.
    vim.api.nvim_set_hl(0, 'GitSignsAdd', { foreground = '#258F4E', background = side_col_highlight.background })
    vim.api.nvim_set_hl(0, 'GitSignsChange', { foreground = '#DBC614', background = side_col_highlight.background })
    vim.api.nvim_set_hl(0, 'GitSignsDelete', { foreground = '#DB4539', background = side_col_highlight.background })
    vim.api.nvim_set_hl(0, 'TroubleIndent', { foreground = side_col_highlight.foreground })
    vim.api.nvim_set_hl(0, 'OctoStatusColumn', { foreground = '#2ac3de', background = side_col_highlight.background })
    -- Make winbar not dim on blur.
    local winbar_hl = vim.api.nvim_get_hl(0, { name = 'WinBar' })
    vim.api.nvim_set_hl(0, 'WinBar', { foreground = winbar_hl.fg, background = side_col_highlight.background })
    vim.api.nvim_set_hl(0, 'WinBarNC', { link = 'WinBar' })
    -- Make window separator darker
    vim.api.nvim_set_hl(0, 'WinSeparator', { foreground = '#454d71', bold = true, cterm = { bold = true } })
  end,
}
