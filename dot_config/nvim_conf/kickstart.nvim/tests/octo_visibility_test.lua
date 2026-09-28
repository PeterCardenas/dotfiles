vim.opt.rtp:prepend(vim.fn.getcwd())
local Visibility = require('local.octo_visibility')
local snapshot = {
  focused_workspace_id = 'w1',
  focused_tab_id = 'w1:t1',
  panes = { { pane_id = 'w1:p1', workspace_id = 'w1', tab_id = 'w1:t1' } },
  layouts = { { tab_id = 'w1:t1', zoomed = false, focused_pane_id = 'w1:p2' } },
}
assert(Visibility.herdr_visible(snapshot, 'w1:p1'), 'unfocused split remains visible')
snapshot.layouts[1].zoomed = true
assert(not Visibility.herdr_visible(snapshot, 'w1:p1'), 'zoom hides other panes')
snapshot.layouts[1].focused_pane_id = 'w1:p1'
assert(Visibility.herdr_visible(snapshot, 'w1:p1'), 'zoomed pane remains visible')
snapshot.focused_tab_id = 'w1:t2'
assert(not Visibility.herdr_visible(snapshot, 'w1:p1'), 'hidden tab is not visible')
snapshot.focused_tab_id = 'w1:t1'
snapshot.focused_workspace_id = 'w2'
assert(not Visibility.herdr_visible(snapshot, 'w1:p1'), 'hidden workspace is not visible')
assert(not Visibility.herdr_visible(nil, 'w1:p1'), 'missing snapshot fails closed')
assert(Visibility.tmux_visible('1 1 0 0'), 'unfocused split remains visible')
assert(Visibility.tmux_visible('1 1 1 1'), 'zoomed active pane remains visible')
assert(not Visibility.tmux_visible('1 1 1 0'), 'zoom hides other panes')
assert(not Visibility.tmux_visible('1 0 0 1'), 'inactive window is not visible')
assert(not Visibility.tmux_visible('0 1 0 1'), 'detached session is not visible')
assert(not Visibility.tmux_visible(''), 'failed query fails closed')
local bufnr = vim.api.nvim_get_current_buf()
assert(Visibility.buffer_visible(bufnr), 'current buffer is visible')
vim.cmd('tabnew')
assert(not Visibility.buffer_visible(bufnr), 'buffer in another tab is hidden')

local tmux, tmux_pane, herdr_env, herdr_pane = vim.env.TMUX, vim.env.TMUX_PANE, vim.env.HERDR_ENV, vim.env.HERDR_PANE_ID
vim.env.TMUX, vim.env.TMUX_PANE, vim.env.HERDR_ENV, vim.env.HERDR_PANE_ID = nil, nil, nil, nil
local tracked = vim.api.nvim_create_buf(true, false)
local enabled = false
local changes = {}
local tracked_buffers = { [tracked] = {} }
package.loaded['octo.polling'] = {
  status = function()
    return { enabled = enabled, tracked_count = vim.tbl_count(tracked_buffers), buffers = tracked_buffers }
  end,
  set_enabled = function(value)
    enabled = value
    changes[#changes + 1] = value
  end,
}
Visibility.setup()
vim.api.nvim_exec_autocmds('FocusGained', {})
vim.wait(200, function()
  return #changes > 0
end)
assert(not enabled, 'focused Neovim with a hidden tracked buffer must not start polling')
vim.api.nvim_win_set_buf(0, tracked)
vim.api.nvim_exec_autocmds('BufWinEnter', {})
assert(
  vim.wait(1000, function()
    return enabled
  end),
  'visible tracked buffer starts polling'
)
vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, false))
vim.api.nvim_exec_autocmds('BufWinEnter', {})
vim.wait(300)
assert(enabled, 'briefly hidden tracked buffer keeps polling')
vim.api.nvim_win_set_buf(0, tracked)
vim.api.nvim_exec_autocmds('BufWinEnter', {})
vim.wait(5500)
assert(enabled, 'returning to the tracked buffer cancels the pending stop')
vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, false))
vim.api.nvim_exec_autocmds('BufWinEnter', {})
assert(
  vim.wait(6500, function()
    return not enabled
  end),
  'hidden tracked buffer eventually stops polling'
)
tracked_buffers = {}
enabled = true
vim.api.nvim_exec_autocmds('FocusGained', {})
assert(not enabled, 'no tracked buffers must disable future auto-starts')
vim.env.TMUX, vim.env.TMUX_PANE, vim.env.HERDR_ENV, vim.env.HERDR_PANE_ID = tmux, tmux_pane, herdr_env, herdr_pane
print('octo_visibility: ok')
