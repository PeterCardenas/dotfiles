-- [[ Neovim Ghostty Integration ]]

local Async = require('utils.async')
local Log = require('utils.log')
local Shell = require('utils.shell')

local M = {}
local UPDATE_DEBOUNCE_MS = 50
local FOCUS_GAINED_DELAY_MS = 250

---@type uv.uv_timer_t?
local update_timer = nil
---@type string?
local pending_update_event = nil
local pending_focus_delay = false
local is_navigation_update_in_flight = false
---@type string?
local pending_directions = nil
---@type string?
local pending_context = nil
---@type string?
local last_applied_directions = nil

---@return uv.uv_timer_t
local function get_update_timer()
  if update_timer then
    return update_timer
  end

  update_timer = vim.uv.new_timer()
  if not update_timer then
    error('Failed to create ghostty navigation update timer')
  end

  return update_timer
end

local function clear_scheduled_update()
  pending_update_event = nil
  pending_focus_delay = false
  if update_timer then
    update_timer:stop()
  end
end

---@return string?
local function get_tui_client_pid()
  local is_headless = #vim.api.nvim_list_uis() == 0
  if is_headless then
    return nil
  end
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    local info = vim.api.nvim_get_chan_info(ui.chan)
    if info.client and info.client.name == 'nvim-tui' then
      return info.client.attributes.pid
    end
  end
  error('Failed to find nvim-tui client')
end

---Set ghostty navigation for specific directions (disables all others)
---@async
---@param directions string
---@return boolean, string|nil
local function set_ghostty_navigation(directions)
  Async.scheduler()
  local ok, tui_pid = pcall(get_tui_client_pid)
  if not ok then
    return false, tostring(tui_pid)
  end
  -- If we're headless, don't try to set ghostty navigation
  if not tui_pid then
    return true, nil
  end
  local success, output = Shell.async_cmd('fish', { '-c', 'ghostty_nvim_nav ' .. directions .. ' ' .. tui_pid })
  if not success then
    return false, 'Failed to set ghostty navigation for: ' .. directions .. '\n' .. table.concat(output, '\n')
  end
  return true, nil
end

---@param directions string
---@return boolean, string|nil
local function set_ghostty_navigation_sync(directions)
  local ok, tui_pid = pcall(get_tui_client_pid)
  if not ok then
    return false, tostring(tui_pid)
  end
  if not tui_pid then
    return true, nil
  end
  local success, output = Shell.sync_cmd('fish -c "ghostty_nvim_nav ' .. directions .. ' ' .. tui_pid .. '"')
  if not success then
    return false, 'Failed to set ghostty navigation for: ' .. directions .. '\n' .. table.concat(output, '\n')
  end
  return true, nil
end

---Check if blink.cmp menu is currently visible
---@return boolean
local function is_blink_menu_visible()
  local ok, blink = pcall(require, 'blink.cmp')
  if not ok then
    return false
  end

  return blink.is_menu_visible()
end

---Check if we are in cmdline or cmdwin mode.
---@return boolean
local function is_cmdline_mode()
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'c' then
    return true
  end

  return vim.fn.getcmdwintype() ~= ''
end

---Check if current buffer is an fzf buffer
---@return boolean
local function is_picker_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode
  local filetype = vim.bo[bufnr].filetype
  return filetype == 'fzf' or (filetype == 'TelescopePrompt' and mode == 'i')
end

---@param directions string
---@param context string
local function queue_ghostty_navigation(directions, context)
  pending_directions = directions
  pending_context = context

  if is_navigation_update_in_flight then
    return
  end

  Async.void(
    ---@async
    function()
      while pending_directions ~= nil do
        local next_directions = pending_directions
        local next_context = pending_context or 'ghostty_navigation'
        pending_directions = nil
        pending_context = nil

        if next_directions ~= last_applied_directions then
          is_navigation_update_in_flight = true
          local success, err = set_ghostty_navigation(next_directions)
          is_navigation_update_in_flight = false

          if not success then
            Log.notify_error('[ghostty_navigation] ' .. next_context .. ': ' .. (err or 'Failed to update navigation'))
            return
          end

          last_applied_directions = next_directions
        end
      end
    end
  )
end

---@class ghostty_nav.EdgeDirections
---@field h boolean
---@field j boolean
---@field k boolean
---@field l boolean

---Check which directions are at the edge (can't navigate further in vim)
---@return ghostty_nav.EdgeDirections Map of direction to whether it's at edge
local function get_edge_directions()
  local current_winnr = vim.fn.winnr()
  local edges = {
    h = vim.fn.winnr('h') == current_winnr,
    l = vim.fn.winnr('l') == current_winnr,
    j = vim.fn.winnr('j') == current_winnr,
    k = vim.fn.winnr('k') == current_winnr,
  }

  local cur_win = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(cur_win)
  if cfg.relative ~= '' then
    edges.h = true
    edges.l = true
    edges.j = true
    edges.k = true
  end

  if is_cmdline_mode() then
    edges.j = false
    edges.k = false
  end

  -- If blink.cmp menu is visible or in fzf buffer, never enable j/k for ghostty (keep them for vim)
  if is_blink_menu_visible() or is_picker_buffer() then
    edges.j = false
    edges.k = false
    if vim.bo.filetype == 'fzf' then
      edges.l = false
    end
  end

  return edges
end

---Build the directions that ghostty should handle right now.
---@return string
local function get_ghostty_navigation_directions()
  local edges = get_edge_directions()

  -- Build list of directions that are at edge
  ---@type string[]
  local to_enable = {}

  for _, dir in ipairs({ 'h', 'j', 'k', 'l' }) do
    if edges[dir] then
      to_enable[#to_enable + 1] = dir
    end
  end

  -- Set ghostty navigation for only the directions at edge (disables all others)
  return table.concat(to_enable, ',')
end

---@param context string
local function update_ghostty_navigation(context)
  queue_ghostty_navigation(get_ghostty_navigation_directions(), context)
end

---@param event_name string
local function schedule_ghostty_navigation_update(event_name)
  pending_update_event = event_name
  pending_focus_delay = pending_focus_delay or event_name == 'FocusGained'

  local delay_ms = pending_focus_delay and FOCUS_GAINED_DELAY_MS or UPDATE_DEBOUNCE_MS
  local timer = get_update_timer()
  timer:stop()
  timer:start(
    delay_ms,
    0,
    vim.schedule_wrap(function()
      local current_event = pending_update_event or event_name
      pending_update_event = nil
      pending_focus_delay = false
      update_ghostty_navigation(current_event)
    end)
  )
end

---Navigate in direction
---@param direction 'h'|'j'|'k'|'l'
local function vim_navigate(direction)
  ---@diagnostic disable-next-line: no-unknown
  local ok, err = pcall(vim.cmd.wincmd, direction)
  if not ok then
    Log.notify_error('[ghostty_navigation] Failed to navigate: ' .. tostring(err))
    return
  end

  -- Update ghostty navigation after window change
  update_ghostty_navigation('Navigate')
end

---Setup keymaps for navigation
local function setup_keymaps()
  local directions = {
    h = 'left',
    j = 'down',
    k = 'up',
    l = 'right',
  }

  -- Normal mode navigation
  for dir, name in pairs(directions) do
    vim.keymap.set({ 'n', 'i' }, '<C-' .. dir .. '>', function()
      vim_navigate(dir)
    end, { silent = true, noremap = true, desc = 'Navigate window ' .. name })
  end

  local term_directions = { 'h', 'l' }

  -- Terminal mode navigation
  for _, dir in ipairs(term_directions) do
    vim.keymap.set('t', '<C-' .. dir .. '>', function()
      -- In terminal mode, we need to leave terminal mode first
      vim.cmd('stopinsert')
      vim_navigate(dir)
    end, { silent = true, noremap = true, desc = 'Navigate window ' .. directions[dir] })
  end
end

---Setup autocommands for focus handling
local function setup_autocommands()
  local group = vim.api.nvim_create_augroup('ghostty_navigator', { clear = true })

  -- Events that should update ghostty navigation (no pattern)
  vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'VimResized', 'VimResume', 'FocusGained', 'TermEnter', 'TermLeave', 'CmdlineEnter', 'CmdlineLeave' }, {
    desc = 'Update ghostty navigation',
    group = group,
    callback = function(args)
      schedule_ghostty_navigation_update(args.event)
    end,
  })

  -- Layout changes where the current window stays the same
  -- WinClosed/WinNew don't trigger WinEnter for the current window,
  -- so edge directions become stale without this.
  vim.api.nvim_create_autocmd({ 'WinClosed', 'WinNew' }, {
    desc = 'Update ghostty navigation after layout change',
    group = group,
    callback = function(args)
      if is_cmdline_mode() then
        return
      end
      -- Defer so the layout is fully settled before recalculating edges
      vim.schedule(function()
        schedule_ghostty_navigation_update(args.event)
      end)
    end,
  })

  -- Events that should enable all ghostty navigation (no pattern)
  vim.api.nvim_create_autocmd({ 'VimSuspend', 'FocusLost' }, {
    desc = 'Enable all ghostty navigation',
    group = group,
    callback = function(args)
      clear_scheduled_update()
      queue_ghostty_navigation('all', args.event)
    end,
  })

  -- Ensure all ghostty navigation is restored before leaving Neovim.
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Enable all ghostty navigation on vim leave',
    group = group,
    callback = function()
      clear_scheduled_update()
      local success, err = set_ghostty_navigation_sync('all')
      if not success then
        Log.notify_error('[ghostty_navigation] VimLeavePre: ' .. (err or 'Failed to enable all navigation'))
      else
        last_applied_directions = 'all'
      end
    end,
  })

  -- Blink completion menu events (with pattern)
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'BlinkCmpMenuOpen', 'BlinkCmpMenuClose' },
    desc = 'Update ghostty navigation on blink menu change',
    group = group,
    callback = function(args)
      if is_cmdline_mode() then
        return
      end
      schedule_ghostty_navigation_update(args.match)
    end,
  })
end

---Setup ghostty navigation
function M.setup()
  -- Only activate if we're in ghostty and not in tmux
  if vim.env.TERM ~= 'xterm-ghostty' or vim.env.TMUX or vim.env.SSH_CONNECTION then
    return
  end

  setup_autocommands()
  setup_keymaps()

  -- Initialize by updating ghostty navigation based on current window
  update_ghostty_navigation('Setup')
end

return M
