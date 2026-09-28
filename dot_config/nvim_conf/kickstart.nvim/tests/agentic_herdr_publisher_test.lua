local root = vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim'
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local tab = vim.api.nvim_get_current_tabpage()
local session = { session_id = 'one', is_generating = true }
package.loaded['agentic.session_registry'] = { sessions = { [tab] = session } }
local pending = require('utils.agentic_pending')
local original_system = vim.system
local original_pane = vim.env.HERDR_PANE_ID
local original_env = vim.env.HERDR_ENV
vim.env.HERDR_ENV, vim.env.HERDR_PANE_ID = '1', 'w1:p1'
local calls = {}
vim.system = function(args, opts, callback)
  calls[#calls + 1] = { args = args, opts = opts, callback = callback }
  return {
    wait = function()
      error('publisher must not block Neovim')
    end,
  }
end

pending.setup()
assert(#calls == 0, 'startup must not release an agent this process never reported')
pending.mark_prompt({ tab_page_id = tab, session_id = 'one' })
assert(#calls == 1 and calls[1].args[3] == 'report-agent', 'prompt reports working')
assert(type(calls[1].callback) == 'function', 'report is asynchronous')
local source = calls[1].args[6]
assert(source:find('agentic.nvim:', 1, true) == 1, 'reports use a process-specific source')
local seq_index = vim.fn.index(calls[1].args, '--seq') + 1
assert(calls[1].args[seq_index + 1]:match('^%d+$'), 'Herdr receives an integer sequence')

session.is_generating = false
pending.recompute()
assert(#calls == 1, 'new state waits for the in-flight report')
calls[1].callback({ code = 0 })
vim.wait(100, function()
  return #calls == 2
end)
assert(#calls == 2 and calls[2].args[3] == 'report-agent', 'latest state follows completion')
assert(vim.tbl_contains(calls[2].args, 'idle'), 'latest state is idle')
calls[2].callback({ code = 0 })
vim.wait(50)
package.loaded['agentic.session_registry'].sessions[tab] = nil
pending.recompute()
vim.wait(100, function()
  return #calls == 3
end)
assert(#calls == 3 and calls[3].args[3] == 'release-agent', 'no prompted sessions releases prior report')
assert(calls[3].args[6] == source, 'release targets the same process-specific source')
assert(vim.tbl_contains(calls[3].args, '--seq'), 'release carries an ordering sequence')
local release_seq_index = vim.fn.index(calls[3].args, '--seq') + 1
assert(tonumber(calls[3].args[release_seq_index + 1]) > tonumber(calls[1].args[seq_index + 1]), 'release follows the report sequence')
calls[3].callback({ code = 0 })
vim.wait(50)
pending.clear()
assert(#calls == 3, 'shutdown does not release twice')

local retry = dofile(root .. '/lua/utils/agentic_pending.lua')
package.loaded['agentic.session_registry'].sessions[tab] = session
retry.setup()
retry.mark_prompt({ tab_page_id = tab, session_id = 'one' })
assert(#calls == 4, 'second publisher reports a prompted session')
calls[4].callback({ code = 1 })
vim.wait(50)
retry.recompute()
assert(#calls == 5, 'failed report retries on the next tick')
assert(calls[4].args[6] == source, 'same process keeps its source')
retry.clear()
assert(#calls == 6 and calls[6].args[3] == 'release-agent', 'shutdown releases an in-flight report')
assert(calls[6].opts.detach, 'shutdown does not block Neovim')
calls[5].callback({ code = 0 })
vim.wait(50)
assert(#calls == 6, 'late completion cannot re-report after shutdown')

vim.system = original_system
vim.env.HERDR_ENV, vim.env.HERDR_PANE_ID = original_env, original_pane
print('agentic herdr publisher: passed')
