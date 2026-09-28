vim.opt.rtp:prepend(vim.fn.getcwd())

local Open = require('utils.open')

assert(Open.resolve_gx_target('http://localhost:3000/path?q=1', '3000/path') == 'http://localhost:3000/path?q=1')
assert(Open.resolve_gx_target('localhost:3000/path', 'localhost') == 'http://localhost:3000/path')
assert(Open.resolve_gx_target('127.0.0.1:8080/api', '127.0.0.1') == 'http://127.0.0.1:8080/api')
assert(Open.resolve_gx_target('[::1]:5173/', '1') == 'http://[::1]:5173/')
assert(Open.resolve_gx_target('README.md:4', 'README.md') == 'README.md')

print('open: ok')
