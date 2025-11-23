local M = {}

M.FT_WITH_LSP = {
  'html',
  'typescript',
  'typescriptreact',
  'javascript',
  'javascriptreact',
  'css',
  'scss',
  'cpp',
  'c',
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
  'glsl',
  'yaml.github',
  'query',
  'terraform',
  'graphql',
}

if vim.fn.has('mac') == 1 then
  M.FT_WITH_LSP[#M.FT_WITH_LSP + 1] = 'swift'
end

--- Applies the given defaults to the completion item, modifying it in place.
---
--- @param item lsp.CompletionItem
--- @param defaults lsp.ItemDefaults?
local function apply_defaults(item, defaults)
  if not defaults then
    return
  end

  item.insertTextFormat = item.insertTextFormat or defaults.insertTextFormat
  item.insertTextMode = item.insertTextMode or defaults.insertTextMode
  item.data = item.data or defaults.data
  if defaults.editRange then
    local textEdit = item.textEdit or {}
    item.textEdit = textEdit
    textEdit.newText = textEdit.newText or item.textEditText or item.insertText
    if defaults.editRange.start then
      textEdit.range = textEdit.range or defaults.editRange
    elseif defaults.editRange.insert then
      textEdit.insert = defaults.editRange.insert
      textEdit.replace = defaults.editRange.replace
    end
  end
end

---@param result vim.lsp.CompletionResult
---@return lsp.CompletionItem[]
function M.completion_result_to_items(result)
  if result.items then
    for _, item in ipairs(result.items) do
      ---@diagnostic disable-next-line: param-type-mismatch
      apply_defaults(item, result.itemDefaults)
    end
    return result.items
  else
    return result
  end
end

return M
