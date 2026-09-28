vim.opt.rtp:prepend(vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim')
local fixture = vim.fn.stdpath('config') .. '/lua/plugins/spec_fixture.lua'
vim.fn.mkdir(vim.fn.fnamemodify(fixture, ':h'), 'p')
vim.fn.writefile({ 'return true' }, fixture)
assert(assert(loadfile(fixture))() == true)
local Staleness = require('utils.config_staleness')
assert(Staleness.is_stale() == false)
local ok, err = xpcall(function()
  vim.fn.writefile({ 'return false -- spec loaded through loadfile' }, fixture)
  Staleness.check()
  assert(Staleness.is_stale(), 'changed loadfile-based plugin spec must mark config stale')
end, debug.traceback)
vim.fn.delete(fixture)
if not ok then
  error(err)
end
print('config_staleness_loadfile: ok')
