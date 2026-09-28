local M = {}

function M.buffer_visible(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return true
    end
  end
  return false
end

function M.tmux_visible(output)
  local attached, active_window, zoomed, active_pane = output:match('^(%d+) (%d+) (%d+) (%d+)')
  return tonumber(attached) ~= nil and tonumber(attached) > 0 and active_window == '1' and (zoomed == '0' or active_pane == '1')
end

function M.herdr_visible(snapshot, pane_id)
  if type(snapshot) ~= 'table' then
    return false
  end
  for _, pane in ipairs(snapshot.panes or {}) do
    if pane.pane_id == pane_id and pane.workspace_id == snapshot.focused_workspace_id and pane.tab_id == snapshot.focused_tab_id then
      for _, layout in ipairs(snapshot.layouts or {}) do
        if layout.tab_id == pane.tab_id then
          return not layout.zoomed or layout.focused_pane_id == pane_id
        end
      end
    end
  end
  return false
end

local function query_visibility(callback)
  local function query_herdr()
    if vim.env.HERDR_ENV ~= '1' or not vim.env.HERDR_PANE_ID then
      callback(true)
      return
    end
    local pane_id = vim.env.HERDR_PANE_ID
    vim.system({ vim.env.HERDR_BIN_PATH or 'herdr', 'api', 'snapshot' }, { text = true }, function(result)
      vim.schedule(function()
        local ok, response = pcall(vim.json.decode, result.stdout or '')
        local snapshot = ok and type(response) == 'table' and response.result and response.result.snapshot
        callback(result.code == 0 and M.herdr_visible(snapshot, pane_id))
      end)
    end)
  end
  if not vim.env.TMUX or not vim.env.TMUX_PANE then
    query_herdr()
    return
  end
  vim.system(
    { 'tmux', 'display-message', '-p', '-t', vim.env.TMUX_PANE, '#{session_attached} #{window_active} #{window_zoomed_flag} #{pane_active}' },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 or not M.tmux_visible(result.stdout or '') then
          callback(false)
        else
          query_herdr()
        end
      end)
    end
  )
end

function M.setup()
  local polling = require('octo.polling')
  local pending = false
  local function update()
    if pending or polling.status().tracked_count == 0 then
      return
    end
    pending = true
    query_visibility(function(visible)
      pending = false
      if visible ~= polling.status().enabled then
        polling.set_enabled(visible)
      end
    end)
  end
  local timer = assert(vim.uv.new_timer())
  timer:start(0, 2500, vim.schedule_wrap(update))
  local group = vim.api.nvim_create_augroup('octo_terminal_visibility', { clear = true })
  vim.api.nvim_create_autocmd({ 'FocusGained', 'FocusLost', 'TabEnter', 'BufWinEnter' }, { group = group, callback = update })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      timer:stop()
      timer:close()
    end,
  })
end

return M
