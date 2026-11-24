vim.opt.rtp:prepend(vim.fn.getcwd())

local Open = require('utils.open')

local doc_dir = vim.fn.tempname()
vim.cmd.edit(vim.fs.joinpath(doc_dir, 'doc.md'))
vim.bo.filetype = 'markdown'
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  '[my link](https://en.wikipedia.org/wiki/Foo_(bar)) [readme](./sub/README.md#usage "Title") ![img](<a b.png>)',
  '[full][Ref] [ref][] <https://auto.example/x> [anchor](#top)',
  '',
  '[ref]: https://ref.example/path',
})

---@param row integer 1-based
---@param text string
---@return string?
local function target_at(row, text)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, true)[1]
  local col = assert(line:find(text, 1, true), text) - 1
  vim.api.nvim_win_set_cursor(0, { row, col })
  return Open.markdown_link_target()
end

local function expect(actual, expected)
  assert(actual == expected, ('expected %s, got %s'):format(vim.inspect(expected), vim.inspect(actual)))
end

expect(target_at(1, 'my link'), 'https://en.wikipedia.org/wiki/Foo_(bar)')
expect(target_at(1, 'wikipedia'), 'https://en.wikipedia.org/wiki/Foo_(bar)')
expect(target_at(1, 'readme]'), vim.fs.joinpath(doc_dir, 'sub/README.md'))
expect(target_at(1, 'img'), vim.fs.joinpath(doc_dir, 'a b.png'))
expect(target_at(2, 'full'), 'https://ref.example/path')
expect(target_at(2, 'Ref]'), 'https://ref.example/path')
expect(target_at(2, 'ref][]'), 'https://ref.example/path')
expect(target_at(2, 'auto.example'), 'https://auto.example/x')
expect(target_at(2, 'anchor'), nil)
expect(target_at(4, 'ref.example'), 'https://ref.example/path')

vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'plain text https://plain.example' })
expect(target_at(1, 'plain.example'), nil)

print('open markdown: ok')
