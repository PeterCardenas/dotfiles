-- [[ Neovim Ghostty Integration ]]

local Async = require('utils.async')
local Shell = require('utils.shell')
local Log = require('utils.log')

local M = {}

---Set ghostty navigation for specific directions (disables all others)
---@async
---@param directions string
---@return boolean, string|nil
local function set_ghostty_navigation(directions)
  local success, output = Shell.async_cmd('fish', { '-c', 'ghostty_nvim_nav ' .. directions })
  if not success then
    return false, 'Failed to set ghostty navigation for: ' .. directions .. '\n' .. table.concat(output, '\n')
  end
  return true, nil
end

---@param directions string
---@return boolean, string|nil
local function set_ghostty_navigation_sync(directions)
  local success, output = Shell.sync_cmd('fish -c "ghostty_nvim_nav ' .. directions .. '"')
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

---Check if current buffer is an fzf buffer
---@return boolean
local function is_picker_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode
  local filetype = vim.bo[bufnr].filetype
  return filetype == 'fzf' or (filetype == 'TelescopePrompt' and mode == 'i')
end

---Check which directions are at the edge (can't navigate further in vim)
---@return table<string, boolean> Map of direction to whether it's at edge
local function get_edge_directions()
  local current_winnr = vim.fn.winnr()
  local edges = {
    h = vim.fn.winnr('h') == current_winnr,
    l = vim.fn.winnr('l') == current_winnr,
    j = vim.fn.winnr('j') == current_winnr,
    k = vim.fn.winnr('k') == current_winnr,
  }

  -- If blink.cmp menu is visible or in fzf buffer, never enable j/k for ghostty (keep them for vim)
  if is_blink_menu_visible() or is_picker_buffer() then
    edges.j = false
    edges.k = false
  end

  return edges
end

---Update ghostty navigation based on current window position
---@async
---@return boolean, string|nil
local function update_ghostty_navigation()
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
  local dirs_str = table.concat(to_enable, ',')
  local ok, err = set_ghostty_navigation(dirs_str)
  if not ok then
    return false, err
  end

  return true, nil
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
  Async.void(
    ---@async
    function()
      local success, error_msg = update_ghostty_navigation()
      if not success then
        Log.notify_error('[ghostty_navigation] ' .. (error_msg or 'Failed to update navigation'))
      end
    end
  )
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
  vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'VimResized', 'VimResume', 'FocusGained', 'TermEnter', 'TermLeave' }, {
    desc = 'Update ghostty navigation',
    group = group,
    callback = function(args)
      Async.void(
        ---@async
        function()
          -- HACK: workaround race between focus lost and focus gained
          if args.event == 'FocusGained' then
            Shell.sleep(250)
          end
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] ' .. args.event .. ': ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })

  -- Events that should enable all ghostty navigation (no pattern)
  vim.api.nvim_create_autocmd({ 'VimSuspend', 'FocusLost' }, {
    desc = 'Enable all ghostty navigation',
    group = group,
    callback = function(args)
      Async.void(
        ---@async
        function()
          local success, err = set_ghostty_navigation('all')
          if not success then
            Log.notify_error('[ghostty_navigation] ' .. args.event .. ': ' .. (err or 'Failed to enable all navigation'))
          end
        end
      )
    end,
  })

  -- VimLeavePre needs special handling with sleep
  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Enable all ghostty navigation on vim leave',
    group = group,
    callback = function()
      local success, err = set_ghostty_navigation_sync('all')
      if not success then
        Log.notify_error('[ghostty_navigation] VimLeavePre: ' .. (err or 'Failed to enable all navigation'))
      end
      vim.cmd('sleep 10m')
    end,
  })

  -- Blink completion menu events (with pattern)
  vim.api.nvim_create_autocmd('User', {
    pattern = { 'BlinkCmpMenuOpen', 'BlinkCmpMenuClose' },
    desc = 'Update ghostty navigation on blink menu change',
    group = group,
    callback = function(args)
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] ' .. args.match .. ': ' .. (err or 'Failed to update navigation'))
          end
        end
      )
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
  Async.void(
    ---@async
    function()
      local success, err = update_ghostty_navigation()
      if not success then
        Log.notify_error('[ghostty_navigation] Setup: ' .. (err or 'Failed to initialize navigation'))
      end
    end
  )
end

return M
