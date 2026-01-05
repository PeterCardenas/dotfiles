-- [[ Neovim Ghostty Integration ]]

local Async = require('utils.async')
local Shell = require('utils.shell')
local Log = require('utils.log')

local M = {}

---Set ghostty navigation for specific directions (disables all others)
---@async
---@param directions string Comma-separated directions (e.g., "h,j,k,l"), "all", or "" to disable all
---@return boolean, string|nil
local function set_ghostty_navigation(directions)
  local success = Shell.async_cmd('fish', { '-c', 'ghostty_nvim_nav ' .. directions })
  if not success then
    return false, 'Failed to set ghostty navigation for: ' .. directions
  end
  return true, nil
end

---Check which directions are at the edge (can't navigate further in vim)
---@return table<string, boolean> Map of direction to whether it's at edge
local function get_edge_directions()
  local edges = {}
  local current_winnr = vim.fn.winnr()

  -- Check each direction by comparing window numbers
  edges.h = (vim.fn.winnr('h') == current_winnr)
  edges.j = (vim.fn.winnr('j') == current_winnr)
  edges.k = (vim.fn.winnr('k') == current_winnr)
  edges.l = (vim.fn.winnr('l') == current_winnr)

  return edges
end

---Update ghostty navigation based on current window position
---@async
---@return boolean, string|nil
local function update_ghostty_navigation()
  local edges = get_edge_directions()

  -- Build list of directions that are at edge
  local to_enable = {}

  for _, dir in ipairs({ 'h', 'j', 'k', 'l' }) do
    if edges[dir] then
      table.insert(to_enable, dir)
    end
  end

  -- Set ghostty navigation for only the directions at edge (disables all others)
  local dirs_str = #to_enable > 0 and table.concat(to_enable, ',') or ''
  local ok, err = set_ghostty_navigation(dirs_str)
  if not ok then
    return false, err
  end

  return true, nil
end

---Navigate in direction
---@param direction string 'h'|'j'|'k'|'l'
local function vim_navigate(direction)
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
  local directions = { 'h', 'j', 'k', 'l' }

  -- Normal mode navigation
  for _, dir in ipairs(directions) do
    vim.keymap.set('n', '<C-' .. dir .. '>', function()
      vim_navigate(dir)
    end, { silent = true, noremap = true, desc = 'Navigate ' .. dir })
  end

  -- Insert mode navigation
  for _, dir in ipairs(directions) do
    vim.keymap.set('i', '<C-' .. dir .. '>', function()
      vim.cmd('stopinsert')
      vim_navigate(dir)
    end, { silent = true, noremap = true, desc = 'Navigate ' .. dir .. ' from insert' })
  end

  -- Terminal mode navigation
  for _, dir in ipairs(directions) do
    vim.keymap.set('t', '<C-' .. dir .. '>', function()
      -- In terminal mode, we need to leave terminal mode first
      vim.cmd('stopinsert')
      vim_navigate(dir)
    end, { silent = true, noremap = true, desc = 'Navigate ' .. dir .. ' from terminal' })
  end
end

---Setup autocommands for focus handling
local function setup_autocommands()
  local group = vim.api.nvim_create_augroup('ghostty_navigator', { clear = true })

  vim.api.nvim_create_autocmd('VimEnter', {
    desc = 'Initialize ghostty navigation on vim enter',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] VimEnter: ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('WinEnter', {
    desc = 'Update ghostty navigation on window enter',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] WinEnter: ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    desc = 'Update ghostty navigation on vim resize',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] VimResized: ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    desc = 'Enable all ghostty navigation on vim leave',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = set_ghostty_navigation('all')
          if not success then
            Log.notify_error('[ghostty_navigation] VimLeavePre: ' .. (err or 'Failed to enable all navigation'))
          end
        end
      )
      vim.cmd('sleep 10m')
    end,
  })

  vim.api.nvim_create_autocmd('VimSuspend', {
    desc = 'Enable all ghostty navigation on vim suspend',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = set_ghostty_navigation('all')
          if not success then
            Log.notify_error('[ghostty_navigation] VimSuspend: ' .. (err or 'Failed to enable all navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('VimResume', {
    desc = 'Update ghostty navigation on vim resume',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] VimResume: ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('FocusLost', {
    desc = 'Enable all ghostty navigation on focus lost',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = set_ghostty_navigation('all')
          if not success then
            Log.notify_error('[ghostty_navigation] FocusLost: ' .. (err or 'Failed to enable all navigation'))
          end
        end
      )
    end,
  })

  vim.api.nvim_create_autocmd('FocusGained', {
    desc = 'Update ghostty navigation on focus gained',
    group = group,
    callback = function()
      Async.void(
        ---@async
        function()
          local success, err = update_ghostty_navigation()
          if not success then
            Log.notify_error('[ghostty_navigation] FocusGained: ' .. (err or 'Failed to update navigation'))
          end
        end
      )
    end,
  })
end

---Setup ghostty navigation
function M.setup()
  -- Only activate if we're in ghostty and not in tmux
  if vim.env.TERM ~= 'xterm-ghostty' then
    return
  end

  if vim.env.TMUX_PANE and vim.env.TMUX then
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
