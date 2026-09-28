vim.opt.rtp:prepend(vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim')
local Staleness = require('utils.config_staleness')
assert(Staleness.is_stale() == false, 'config should start fresh')
local fixture = vim.fn.stdpath('config') .. '/tests/stale_fixture.lua'
local unrelated_fixture = vim.fn.stdpath('config') .. '/tests/stale_fixture.vim'
vim.fn.mkdir(vim.fn.fnamemodify(fixture, ':h'), 'p')
local ok, err = xpcall(function()
  vim.fn.writefile({ 'let g:stale_fixture = v:true' }, unrelated_fixture)
  vim.cmd('source ' .. vim.fn.fnameescape(unrelated_fixture))
  Staleness.check()
  vim.fn.writefile({ 'let g:stale_fixture = v:false -- unrelated change' }, unrelated_fixture)
  Staleness.check()
  assert(Staleness.is_stale() == false, 'non-Lua config scripts should be ignored')
  vim.fn.writefile({ 'return true' }, fixture)
  Staleness.check()
  assert(Staleness.is_stale() == true, 'new Lua config file should mark stale even before loading')
end, debug.traceback)
vim.fn.delete(fixture)
vim.fn.delete(unrelated_fixture)
if not ok then
  error(err)
end
print('config_staleness: ok')
