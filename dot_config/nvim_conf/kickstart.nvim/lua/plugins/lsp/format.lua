LspMethod = vim.lsp.protocol.Methods

---@param bufnr integer
---@param ls_name string
---@param action_type string
---@param on_complete? function
local function commit_code_action_edit(bufnr, ls_name, action_type, on_complete)
  local params = vim.lsp.util.make_range_params()
  params.context = { only = { action_type }, diagnostics = {} }
  local clients = vim.lsp.get_clients({
    bufnr = bufnr,
    name = ls_name,
    method = LspMethod.textDocument_codeAction,
  })
  if #clients == 0 then
    if on_complete then
      on_complete()
    end
    return
  end
  local completion_count = 0
  for _, client in ipairs(clients) do
    ---@param err any
    ---@param ls_results lsp.CodeAction[]
    client.request(LspMethod.textDocument_codeAction, params, function(err, ls_results, _, _)
      if err then
        vim.notify('Error running' .. ls_name .. ' code action: ' .. err, vim.log.levels.ERROR)
      end
      for _, ls_result in ipairs(ls_results or {}) do
        if ls_result.edit then
          local offset_encoding = (vim.lsp.get_client_by_id(client.id) or {}).offset_encoding or 'utf-16'
          vim.lsp.util.apply_workspace_edit(ls_result.edit, offset_encoding)
        end
      end
      completion_count = completion_count + 1
      if completion_count == #clients and on_complete then
        on_complete()
      end
    end, bufnr)
  end
end

---Organizes go imports.
---@param bufnr integer
---@param on_complete? function
local function format_go_imports(bufnr, on_complete)
  commit_code_action_edit(bufnr, 'gopls', 'source.organizeImports', on_complete)
end

---Fix all auto-fixable ruff lsp errors.
---@param bufnr integer
---@param on_complete? function
local function fix_ruff_errors(bufnr, on_complete)
  commit_code_action_edit(bufnr, 'ruff_lsp', 'source.organizeImports', function()
    commit_code_action_edit(bufnr, 'ruff_lsp', 'source.fixAll', on_complete)
  end)
end

local M = {}

---@param bufnr integer
function M.format(bufnr)
  -- TODO(@PeterPCardenas): Spawn a separate thread instead of using callbacks.
  format_go_imports(bufnr, function()
    fix_ruff_errors(bufnr, function()
      vim.lsp.buf.format({
        bufnr = bufnr,
        async = true,
      })
    end)
  end)
end

return M
