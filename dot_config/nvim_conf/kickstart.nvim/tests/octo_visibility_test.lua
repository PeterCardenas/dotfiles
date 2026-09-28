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
print('octo_visibility: ok')
