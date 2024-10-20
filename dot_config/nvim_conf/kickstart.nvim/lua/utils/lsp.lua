local M = {}

M.FT_WITH_LSP = {
  'typescript',
  'typescriptreact',
  'javascript',
  'javascriptreact',
  'css',
  'scss',
  'cpp',
  'python',
  'go',
  'json',
  'lua',
  'bzl',
  'mdx',
  'markdown',
  'markdown.mdx',
  'rust',
  'yaml',
  'sh',
  'fish',
  'toml',
  'jsonc',
  'bazelrc',
  'proto',
  'zig',
  'vim',
}

if vim.fn.has('mac') == 1 then
  table.insert(M.FT_WITH_LSP, 'swift')
end

return M
