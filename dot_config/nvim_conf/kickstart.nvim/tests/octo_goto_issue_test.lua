vim.opt.rtp:prepend(vim.fn.getcwd())
local GotoIssue = require('local.octo_goto_issue')

local opened = {}
package.loaded['octo.utils'] = {
  get_current_repo = function()
    return 'owner/repo'
  end,
  extract_issue_at_cursor = function(repo)
    return repo, 42
  end,
  open_buffer = function(repo, number, opts)
    opened[#opened + 1] = { repo = repo, number = number, winid = opts and opts.winid, current = vim.api.nvim_get_current_win() }
  end,
}

local source_winid = vim.api.nvim_get_current_win()
GotoIssue.go_to_issue()
assert(opened[1].winid == source_winid, 'non-floating window opens in place')

vim.cmd('vsplit')
local other_winid = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(source_winid)
local float_winid = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })
GotoIssue.go_to_issue()
assert(opened[2].winid == source_winid, 'float opens in the window it was entered from, not ' .. tostring(opened[2].winid))
assert(opened[2].current == source_winid, 'focus moves to the source window')
assert(opened[2].winid ~= other_winid and opened[2].winid ~= float_winid, 'never targets the float or an unrelated split')

vim.api.nvim_set_current_win(source_winid)
local outer_float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })
vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 4, col = 1, width = 10, height = 2 })
GotoIssue.go_to_issue()
assert(opened[3].winid ~= outer_float, 'nested floats fall back to a non-floating window')
assert(vim.api.nvim_win_get_config(opened[3].winid).relative == '', 'fallback window is not floating')

print('octo_goto_issue_test: ok')
vim.cmd('qa!')
