-- [[ Neovim TMUX Integration ]]

local Async = require('utils.async')
local Colors = require('utils.colorscheme')
local Shell = require('utils.shell')
local Log = require('utils.log')

---@class TmuxCmdInfo
---@field pane_id string
---@field socket string

---@class TmuxCmd : TmuxCmdInfo
local TmuxCmd = {}
TmuxCmd.__index = TmuxCmd

---@param pane_id string
---@param tmux_var string
---@return TmuxCmd
function TmuxCmd:new(pane_id, tmux_var)
  local socket = vim.split(tmux_var, ',')[1]
  ---@type TmuxCmdInfo
  local instance = {
    pane_id = pane_id,
    socket = socket,
  }
  setmetatable(instance, self)
  return instance ---@type TmuxCmd
end

function TmuxCmd:with_socket(subcommand)
  return 'tmux -S ' .. self.socket .. ' ' .. subcommand
end

function TmuxCmd:with_set_option(subcommand)
  return self:with_socket('set-option -t ' .. self.pane_id .. ' -p ' .. subcommand)
end

---@async
---@param subcommand string
---@return boolean
function TmuxCmd:set_option(subcommand)
  local success, output = Shell.async_cmd('bash', { '-c', self:with_set_option(subcommand) })
  if not success then
    Log.notify_error('Failed to set tmux option: ' .. vim.inspect(output))
  end
  return success
end

---@param subcommand string
---@return boolean
function TmuxCmd:set_option_sync(subcommand)
  local success, output = Shell.sync_cmd('bash -c "' .. self:with_set_option(subcommand) .. '"')
  if not success then
    vim.notify('Failed to set tmux option: ' .. vim.inspect(output), vim.log.levels.ERROR)
  end
  return success
end

---@async
function TmuxCmd:set_is_vim()
  local success, output = Shell.async_cmd('bash', {
    '-c',
    self:with_set_option('@disable_vertical_pane_navigation yes') .. ' && ' .. self:with_set_option('@disable_horizontal_pane_navigation yes'),
  })
  if not success then
    Log.notify_error('Failed to set is_vim: ' .. vim.inspect(output))
  end
end

---@async
function TmuxCmd:unset_is_vim()
  local success, output = Shell.async_cmd('bash', {
    '-c',
    self:with_set_option('-u @disable_vertical_pane_navigation') .. ' && ' .. self:with_set_option('-u @disable_horizontal_pane_navigation'),
  })
  if not success then
    Log.notify_error('Failed to unset is_vim: ' .. vim.inspect(output))
  end
end

function TmuxCmd:unset_is_vim_sync()
  Shell.sync_cmd(
    'bash -c "'
      .. self:with_set_option('-u @disable_vertical_pane_navigation')
      .. ' && '
      .. self:with_set_option('-u @disable_horizontal_pane_navigation')
      .. '"'
  )
end

local nvim_is_open = true

local function set_is_vim()
  nvim_is_open = true
  local tmux_cmd = TmuxCmd:new(vim.env.TMUX_PANE, vim.env.TMUX)
  Async.void(
    ---@async
    function()
      tmux_cmd:set_is_vim()
    end
  )
end

local function unset_is_vim_sync()
  nvim_is_open = false
  local tmux_cmd = TmuxCmd:new(vim.env.TMUX_PANE, vim.env.TMUX)

  tmux_cmd:unset_is_vim_sync()
end

local function setup_tmux_autocommands()
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
      unset_is_vim_sync()
      -- Hack for making sure vim doesn't exit with a non-zero exit code.
      -- Reference: https://github.com/neovim/neovim/issues/21856#issuecomment-1514723887
      vim.cmd('sleep 10m')
    end,
  })
  vim.api.nvim_create_autocmd('VimSuspend', {
    desc = 'Tell TMUX we suspended neovim',
    group = tmux_navigator_group,
    callback = unset_is_vim_sync,
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
      Colors.set_unfocused_colors()
    end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    desc = 'Brighten the colors to appear focused',
    group = tmux_navigator_group,
    callback = function()
      Colors.set_focused_colors()
    end,
  })
end

---@async
local function update_ssh_connection_from_tmux()
  local success, output = Shell.async_cmd('fish', { '-c', "tmux showenv | string match -rg '^SSH_CONNECTION=(.*?)$'" })
  if not success then
    vim.schedule(function()
      vim.env.SSH_CONNECTION = nil
    end)
    return
  end
  if #output ~= 1 then
    Log.notify_error('Could not get SSH_CONNECTION from tmux env' .. vim.inspect(output))
    return
  end
  local tmux_ssh_connection = output[1]
  vim.schedule(function()
    if tmux_ssh_connection == '' then
      vim.env.SSH_CONNECTION = nil
      return
    end
    vim.env.SSH_CONNECTION = tmux_ssh_connection
  end)
end

---@async
local function update_display_from_tmux()
  local success, output = Shell.async_cmd('fish', { '-c', "tmux showenv | string match -rg '^DISPLAY=(.*?)$'" })
  if not success then
    vim.schedule(function()
      vim.env.DISPLAY = nil
    end)
    return
  end
  if #output ~= 1 then
    Log.notify_error('Could not get DISPLAY from tmux env' .. vim.inspect(output))
    return
  end
  local tmux_display = output[1]
  vim.schedule(function()
    if tmux_display == '' then
      vim.env.DISPLAY = nil
      return
    end
    vim.env.DISPLAY = tmux_display
  end)
end

local function poll_update_tmux_env()
  local tmux_cmd = TmuxCmd:new(vim.env.TMUX_PANE, vim.env.TMUX)
  Async.run(
    ---@async
    function()
      update_ssh_connection_from_tmux()
      update_display_from_tmux()
      if nvim_is_open then
        tmux_cmd:set_is_vim()
      end
      Shell.sleep(1000)
    end,
    poll_update_tmux_env
  )
end

---@type LazyPluginSpec
return {
  -- Easy navigation between splits.
  'alexghergh/nvim-tmux-navigation',
  cond = function()
    return vim.env.TMUX_PANE and vim.env.TMUX
  end,
  event = 'VeryLazy',
  config = function()
    setup_tmux_autocommands()
    Async.void(poll_update_tmux_env)
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
    local insert_tmux_directions = { 'h', 'j', 'k', 'l' }
    local directions = { 'Left', 'Down', 'Up', 'Right' }
    for index, direction in ipairs(insert_tmux_directions) do
      vim.keymap.set('i', '<C-' .. direction .. '>', function()
        require('nvim-tmux-navigation')['NvimTmuxNavigate' .. directions[index]]()
      end, { silent = true, noremap = true })
    end
    local terminal_tmux_directions = { 'h', 'l' }
    for _, direction in ipairs(terminal_tmux_directions) do
      vim.keymap.set('t', '<C-' .. direction .. '>', function()
        require('nvim-tmux-navigation.tmux_util').tmux_change_pane(direction)
      end, { silent = true, noremap = true })
    end
  end,
}
