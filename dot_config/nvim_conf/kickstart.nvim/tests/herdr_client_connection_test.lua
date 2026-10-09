local root = vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim'
local success = false
local output = {}
local detection_calls = 0
package.loaded['utils.async'] = {
  void = function(callback)
    callback()
  end,
  run = function(callback, on_done)
    callback()
    on_done()
  end,
}
package.loaded['utils.shell'] = {
  async_cmd = function()
    detection_calls = detection_calls + 1
    return success, output
  end,
}
local navigation = dofile(root .. '/lua/local/herdr_navigation.lua')
navigation.setup()

vim.env.SSH_CONNECTION = 'client 1 server 2'
vim.api.nvim_exec_autocmds('VimEnter', { group = 'herdr_client_connection' })
vim.wait(100, function()
  return false
end)
assert(vim.env.SSH_CONNECTION == 'client 1 server 2', 'failed detection must retain last connection')

success = true
vim.api.nvim_exec_autocmds('VimEnter', { group = 'herdr_client_connection' })
vim.wait(100, function()
  return false
end)
assert(vim.env.SSH_CONNECTION == nil, 'successful local detection must clear connection')

output = { 'client 3 server 4' }
vim.api.nvim_exec_autocmds('VimEnter', { group = 'herdr_client_connection' })
vim.wait(100, function()
  return false
end)
assert(vim.env.SSH_CONNECTION == 'client 3 server 4', 'successful SSH detection must refresh connection')

-- Herdr can hand input to another attached client without a Neovim FocusGained event.
-- VimEnter must start polling on its own rather than only performing one refresh.
navigation.setup()
vim.api.nvim_exec_autocmds('VimEnter', { group = 'herdr_client_connection' })
output = {}
vim.wait(1250, function()
  return vim.env.SSH_CONNECTION == nil
end)
assert(vim.env.SSH_CONNECTION == nil, 'local client must replace SSH origin without FocusGained')

vim.api.nvim_exec_autocmds('FocusLost', { group = 'herdr_client_connection' })
local calls_after_focus_lost = detection_calls
vim.wait(1150, function()
  return false
end)
assert(detection_calls == calls_after_focus_lost, 'hidden Neovim must stop polling')
