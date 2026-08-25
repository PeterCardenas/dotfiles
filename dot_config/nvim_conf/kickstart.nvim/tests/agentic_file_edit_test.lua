vim.opt.rtp:prepend(vim.fn.getcwd())

local captured
package.loaded['agentic'] = {
  setup = function(config)
    captured = config
  end,
}

local specs = dofile(vim.fn.getcwd() .. '/lua/plugins/sg.lua')
specs[2].config()

local events = {}
local original_exec_autocmds = vim.api.nvim_exec_autocmds
vim.api.nvim_exec_autocmds = function(event, opts)
  events[#events + 1] = { event = event, pattern = opts.pattern, path = opts.data.path }
end

captured.hooks.on_file_edit({ file_path = 'edit tracked.md' })
captured.hooks.on_file_edit({ file_path = 'write tracked.md' })
captured.hooks.on_file_edit({ file_path = 'edit write tracked.md' })
captured.hooks.on_file_edit({ file_path = 'write edit tracked.md' })
captured.hooks.on_file_edit({ file_path = 'tracked.md' })
vim.api.nvim_exec_autocmds = original_exec_autocmds

assert(events[1].event == 'User', 'callback should emit a User event')
assert(events[1].pattern == 'ChezmoiApplyPath', 'callback should emit the ChezmoiApplyPath pattern')
assert(events[1].path == 'tracked.md', 'edit prefix should be stripped')
assert(events[2].path == 'tracked.md', 'write prefix should be stripped')
assert(events[3].path == 'write tracked.md', 'only the leading edit prefix should be stripped')
assert(events[4].path == 'edit tracked.md', 'only the leading write prefix should be stripped')
assert(events[5].path == 'tracked.md', 'unprefixed path should stay unchanged')
print('agentic_file_edit: ok')
