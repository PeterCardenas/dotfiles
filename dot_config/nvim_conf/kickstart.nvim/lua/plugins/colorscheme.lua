---@type LazyPluginSpec
return {
  'folke/tokyonight.nvim',
  lazy = false,
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight-storm')
    -- Make comments foreground brighter.
    vim.cmd([[highlight Comment cterm=italic gui=italic guifg=#7c7c7c]])
    -- More contrast for selected tab.
    vim.cmd([[highlight TabLineSel guifg=#e0e0e0 guibg=#26355E]])
    -- Make tab title foreground brighter.
    vim.cmd([[highlight TabLine guifg=#7c7c7c guibg=#161F38]])
    -- Make git signs foreground brighter.
    vim.cmd([[highlight GitSignsAdd guifg=#258F4E]])
    vim.cmd([[highlight GitSignsChange guifg=#DBC614]])
    vim.cmd([[highlight GitSignsDelete guifg=#DB4539]])
    -- Make git blame foreground brighter.
    vim.cmd([[highlight GitSignsCurrentLineBlame guifg=#7c7c7c]])
    -- Make leap backdrop foreground light grey (in case I forget the key to press lol).
    vim.cmd([[highlight LeapBackdrop guifg=#5C5C5C]])
    -- Add red close button highlight.
    vim.cmd([[highlight TabLineClose guifg=#DB4539]])
  end,
}
