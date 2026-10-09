-- Native Herdr pane navigation: Neovim owns splits before Herdr owns panes.
-- Loaded only when HERDR_ENV=1 with HERDR_PANE_ID set.
local Async = require('utils.async')
local Shell = require('utils.shell')
local M = {}

local directions = {
  left = 'h',
  down = 'j',
  up = 'k',
  right = 'l',
}

local function focus_herdr(direction)
  local herdr = vim.env.HERDR_BIN_PATH
  if not herdr or herdr == '' then
    herdr = 'herdr'
  end
  local pane_id = vim.env.HERDR_PANE_ID
  vim.fn.system({ herdr, 'pane', 'zoom', '--off', '--pane', pane_id })
  vim.fn.system({ herdr, 'pane', 'focus', '--direction', direction, '--pane', pane_id })
end

local function is_floating_non_fzf()
  local config = vim.api.nvim_win_get_config(0)
  return config.relative ~= '' and vim.bo.filetype ~= 'fzf'
end

-- Keep vim.env in step with whichever Herdr client is being driven, so tools
-- that branch on SSH_CONNECTION (wl-paste, osc52_copy) target that client's
-- machine instead of the one this pane happened to start under.
---@async
local function refresh_ssh_connection()
  local success, output = Shell.async_cmd('herdr-client-connection', {})
  if not success then return end -- Unknown client: retain the last confirmed origin.
  local ssh_connection = output[1]
  vim.schedule(function()
    vim.env.SSH_CONNECTION = (ssh_connection and ssh_connection ~= '') and ssh_connection or nil
  end)
end

local connection_poll_generation = 0

local function start_ssh_connection_polling()
  connection_poll_generation = connection_poll_generation + 1
  local generation = connection_poll_generation
  local function poll()
    if generation ~= connection_poll_generation then return end
    Async.run(refresh_ssh_connection, function()
      if generation == connection_poll_generation then
        vim.defer_fn(poll, 1000)
      end
    end)
  end
  poll()
end

local function stop_ssh_connection_polling()
  connection_poll_generation = connection_poll_generation + 1
end

function M.navigate(direction)
  local key = directions[direction]
  if not key then
    error('unknown Herdr navigation direction: ' .. tostring(direction))
  end
  if is_floating_non_fzf() then
    focus_herdr(direction)
    return
  end
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd('wincmd ' .. key)
  if vim.api.nvim_get_current_win() == current_window then
    focus_herdr(direction)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('herdr_client_connection', { clear = true })
  -- Start at VimEnter: Herdr can switch clients without sending FocusGained.
  -- FocusLost stops polling so hidden workspaces do not delay redraws.
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    callback = start_ssh_connection_polling,
  })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = start_ssh_connection_polling,
  })
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = stop_ssh_connection_polling,
  })
  for direction, key in pairs(directions) do
    vim.keymap.set({ 'n', 'i' }, '<C-' .. key .. '>', function()
      M.navigate(direction)
    end, { silent = true, noremap = true })
    vim.keymap.set('t', '<C-' .. key .. '>', function()
      if (key == 'j' or key == 'k') and vim.bo.filetype == 'fzf' then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-' .. key .. '>', true, false, true), 'nt', false)
        return
      end
      M.navigate(direction)
    end, { silent = true, noremap = true })
  end
end

return M
