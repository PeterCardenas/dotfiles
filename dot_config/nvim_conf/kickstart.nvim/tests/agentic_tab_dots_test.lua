local root = vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim'
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
package.path = vim.fn.expand('~/.local/share/nvim/lazy/lualine.nvim/lua/?.lua') .. ';' .. package.path

local registry = { sessions = {} }
package.loaded['agentic.session_registry'] = registry
local pending = require('utils.agentic_pending')
local first = vim.api.nvim_get_current_tabpage()
vim.cmd.tabnew()
local second = vim.api.nvim_get_current_tabpage()
vim.cmd.tabnew()
local third = vim.api.nvim_get_current_tabpage()

local function dots()
  return pending.tab_dots()
end

assert(dots():find('  ', 1, true), 'one dot per tab, active tab filled')
registry.sessions[first] = { session_id = 'one', is_generating = true }
registry.sessions[second] = { session_id = 'two', is_generating = false }
assert(dots():find('DiagnosticError', 1, true) == nil, 'unprompted agent is idle')
pending.mark_prompt({ tab_page_id = first, session_id = 'one' })
pending.mark_prompt({ tab_page_id = second, session_id = 'two' })
local rendered = dots()
assert(rendered:find('DiagnosticOk#', 1, true), 'working tab is green')
assert(rendered:find('DiagnosticError#', 1, true), 'finished tab is red')
assert(rendered:find('', 1, true), 'idle active tab remains filled')
vim.api.nvim_set_current_tabpage(first)
assert(dots():find('DiagnosticOk#', 1, true), 'selected working tab is filled')
registry.sessions[first] = { session_id = 'replacement', is_generating = false }
assert(not dots():find('DiagnosticOk', 1, true), 'old prompt does not color replacement session')
vim.api.nvim_set_current_tabpage(third)
vim.cmd.tabclose()
assert(select(2, dots():gsub('', '')) == 1, 'closed tab disappears')
print('agentic tab dots: passed')
