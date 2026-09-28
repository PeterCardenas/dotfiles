vim.opt.rtp:prepend(vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim')
local fixture = vim.fn.stdpath('config') .. '/timer_fixture.lua'
vim.fn.mkdir(vim.fn.fnamemodify(fixture, ':h'), 'p')
vim.fn.writefile({ 'return true' }, fixture)
local Staleness = require('utils.config_staleness')
local ok, err = xpcall(function()
  vim.fn.writefile({ 'return false -- changed after startup' }, fixture)
  vim.wait(1500)
  assert(not Staleness.is_stale(), 'config must not be polled after one second')
  assert(vim.wait(9500, Staleness.is_stale, 100), 'config must be polled within ten seconds')
end, debug.traceback)
vim.fn.delete(fixture)
if not ok then
  error(err)
end
print('config_staleness_interval: ok')
