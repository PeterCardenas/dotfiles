-- [[ Neovim TMUX Integration ]]

---Create a tmux command with the given subcommand prepended with the tmux socket path.
---@param subcommand string
---@return string
local function with_tmux_socket(subcommand)
  local tmux_socket = vim.fn.split(vim.env.TMUX, ',')[1]
  if not tmux_socket then
    error('TMUX socket is not found in env ' .. vim.env.TMUX)
  end
  return 'tmux -S ' .. tmux_socket .. ' ' .. subcommand
end

---Create a tmux set-option command with the given subcommand prepended with the tmux pane id and tmux socket path.
---@param subcommand string
---@return string
local function with_tmux_set_option(subcommand)
  local tmux_pane_id = vim.env.TMUX_PANE
  if not tmux_pane_id then
    error('TMUX_PANE is not set')
  end
  return with_tmux_socket('set-option -t ' .. tmux_pane_id .. ' -p ' .. subcommand)
end

local function set_is_vim()
  local was_success, error_obj = pcall(function()
    -- Set shell to bash for tmux navigation to be fast.
    -- Reference: https://github.com/christoomey/vim-tmux-navigator/issues/72#issuecomment-873841679
    -- TODO: Ideally fish isn't that slow, maybe we there's a way to make startup faster.
    vim.opt.shell = '/bin/bash'
    local strict_cmd = require('utils.shell').strict_cmd
    strict_cmd(with_tmux_set_option('@disable_vertical_pane_navigation yes'))
    strict_cmd(with_tmux_set_option('@disable_horizontal_pane_navigation yes'))
    vim.opt.shell = 'fish'
  end)
  if not was_success then
    vim.notify('Failed to set is_vim, error: ' .. vim.inspect(error_obj), vim.log.levels.ERROR)
  end
end

local function unset_is_vim()
  local was_success, error_obj = pcall(function()
    -- Set shell to bash for tmux navigation to be fast.
    -- Reference: https://github.com/christoomey/vim-tmux-navigator/issues/72#issuecomment-873841679
    vim.opt.shell = '/bin/bash'
    local strict_cmd = require('utils.shell').strict_cmd
    strict_cmd(with_tmux_set_option('-u @disable_vertical_pane_navigation'))
    strict_cmd(with_tmux_set_option('-u @disable_horizontal_pane_navigation'))
    vim.opt.shell = 'fish'
  end)
  if not was_success then
    vim.notify('Failed to unset is_vim, error: ' .. vim.inspect(error_obj), vim.log.levels.ERROR)
  end
end

local nvim_is_open = true
local tmux_navigator_group = vim.api.nvim_create_augroup('tmux_navigator_is_vim', { clear = true })
vim.api.nvim_create_autocmd('VimEnter', {
  desc = 'Tell TMUX we entered neovim',
  group = tmux_navigator_group,
  callback = function ()
    nvim_is_open = true
    set_is_vim()
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  desc = 'Tell TMUX we left neovim',
  group = tmux_navigator_group,
  callback = function()
    nvim_is_open = false
    unset_is_vim()
    -- Hack for making sure vim doesn't exit with a non-zero exit code.
    -- Reference: https://github.com/neovim/neovim/issues/21856#issuecomment-1514723887
    vim.cmd('sleep 10m')
  end,
})
vim.api.nvim_create_autocmd('VimSuspend', {
  desc = 'Tell TMUX we suspended neovim',
  group = tmux_navigator_group,
  callback = function ()
    nvim_is_open = false
    unset_is_vim()
  end,
})
vim.api.nvim_create_autocmd('VimResume', {
  desc = 'Tell TMUX we resumed neovim',
  group = tmux_navigator_group,
  callback = function()
    nvim_is_open = true
    set_is_vim()
  end,
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

TMUX_TIMER_ID = nil

local function poll_update_tmux_env()
  if TMUX_TIMER_ID ~= nil then
    vim.fn.timer_stop(TMUX_TIMER_ID)
  end
  TMUX_TIMER_ID = vim.fn.timer_start(1000, vim.schedule_wrap(function()
    update_display_from_tmux()

    -- The vim pane option is only set when vim is open.
    if nvim_is_open then
      set_is_vim()
    end
  end), { ["repeat"] = -1 })
  if TMUX_TIMER_ID == -1 then
    vim.notify('Failed to start timer for updating tmux env', vim.log.levels.ERROR)
  end
end

poll_update_tmux_env()

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
