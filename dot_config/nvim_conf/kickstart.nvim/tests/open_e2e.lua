local target = 'http://localhost:9/gx-diagnostic'
local output = assert(vim.fn.getenv('GX_E2E_OUTPUT'))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { target })
vim.api.nvim_win_set_cursor(0, { 1, 10 })
vim.cmd('normal gx')

assert(vim.wait(3000, function()
  return vim.fn.filereadable(output) == 1
end, 10), 'fake gio did not receive gx target')

local received = vim.fn.readfile(output)
assert(vim.deep_equal(received, {
  'display=:1 wayland=wayland-0 arg=' .. target,
}))

print('open e2e: ok')
vim.cmd('qa!')
