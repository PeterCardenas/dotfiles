-- [[ Neovim TMUX Integration ]]
local function set_is_vim()
  -- Set shell to bash for tmux navigation to be fast.
  -- Reference: https://github.com/christoomey/vim-tmux-navigator/issues/72#issuecomment-873841679
  -- TODO: Ideally fish isn't that slow, maybe we there's a way to make startup faster.
  pcall(function()
    vim.opt.shell = '/bin/bash'
    local tmux_socket = vim.fn.split(vim.env.TMUX, ',')[1]
    vim.fn.system('tmux -S ' .. tmux_socket .. ' set-option -p @disable_vertical_pane_navigation yes')
    vim.fn.system('tmux -S ' .. tmux_socket .. ' set-option -p @disable_horizontal_pane_navigation yes')
    vim.opt.shell = 'fish'
  end)
end

local function unset_is_vim()
  -- Set shell to bash for tmux navigation to be fast.
  -- Reference: https://github.com/christoomey/vim-tmux-navigator/issues/72#issuecomment-873841679
  pcall(function()
    vim.opt.shell = '/bin/bash'
    local tmux_socket = vim.fn.split(vim.env.TMUX, ',')[1]
    vim.fn.system('tmux -S ' .. tmux_socket .. ' set-option -p -u @disable_vertical_pane_navigation')
    vim.fn.system('tmux -S ' .. tmux_socket .. ' set-option -p -u @disable_horizontal_pane_navigation')
    vim.opt.shell = 'fish'
  end)
end

local tmux_navigator_group = vim.api.nvim_create_augroup('tmux_navigator_is_vim', { clear = true })
vim.api.nvim_create_autocmd('VimEnter', {
  desc = 'Tell TMUX we entered neovim',
  group = tmux_navigator_group,
  callback = set_is_vim,
})
vim.api.nvim_create_autocmd('VimLeavePre', {
  desc = 'Tell TMUX we left neovim',
  group = tmux_navigator_group,
  callback = function()
    unset_is_vim()
    -- Hack for making sure vim doesn't exit with a non-zero exit code.
    -- Reference: https://github.com/neovim/neovim/issues/21856#issuecomment-1514723887
    vim.cmd('sleep 10m')
  end,
})
vim.api.nvim_create_autocmd('VimSuspend', {
  desc = 'Tell TMUX we suspended neovim',
  group = tmux_navigator_group,
  callback = unset_is_vim,
})
vim.api.nvim_create_autocmd('VimResume', {
  desc = 'Tell TMUX we resumed neovim',
  group = tmux_navigator_group,
  callback = set_is_vim,
})

vim.api.nvim_create_autocmd('FocusLost', {
  desc = 'Dim the colors to appear unfocused',
  group = tmux_navigator_group,
  callback = function()
    require('utils.colorscheme').set_unfocused_colors()
  end,
})

vim.api.nvim_create_autocmd('FocusGained', {
  desc = 'Brighten the colors to appear focused',
  group = tmux_navigator_group,
  callback = function()
    require('utils.colorscheme').set_focused_colors()
  end,
})

local function update_display_from_tmux()
  local tmux_display = vim.fn.systemlist("tmux showenv | string match -rg '^DISPLAY=(.*?)$'")[1]
  if not tmux_display then
    return
  end
  vim.env.DISPLAY = tmux_display
end

local function poll_tmux_display()
  local res = vim.fn.timer_start(1000, vim.schedule_wrap(function()
    update_display_from_tmux()
  end), { ["repeat"] = -1 })
  if res == -1 then
    vim.notify('Failed to start timer for updating DISPLAY from tmux', vim.log.levels.ERROR)
  end
end

poll_tmux_display()

---@type LazyPluginSpec
return {
  -- Easy navigation between splits.
  'alexghergh/nvim-tmux-navigation',
  config = function()
    require('nvim-tmux-navigation').setup({
      keybindings = {
        left = '<C-h>',
        down = '<C-j>',
        up = '<C-k>',
        right = '<C-l>',
        last_active = '<C-\\>',
        next = '<C-Space>',
      },
    })
  end,
}
