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

local function poll_ssh_connection()
  Async.run(
    ---@async
    function()
      local _, output = Shell.async_cmd('fish', {
        '-c',
        'sync_herdr_ssh_connection; if set -q SSH_CONNECTION; printf "%s\\n" "$SSH_CONNECTION"; else; printf "\\n"; end',
      })
      local ssh_connection = output[1]
      vim.schedule(function()
        vim.env.SSH_CONNECTION = ssh_connection ~= '' and ssh_connection or nil
      end)
      Shell.sleep(1000)
    end,
    poll_ssh_connection
  )
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
  Async.void(poll_ssh_connection)
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
