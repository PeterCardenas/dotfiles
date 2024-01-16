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

local format_diagnostic_autocmd_group = vim.api.nvim_create_augroup('FormatChecker', { clear = true })
local format_diagnostic_namespace = vim.api.nvim_create_namespace('FormatChecker')

---@return integer
local function get_current_lnum()
  local lnum = vim.fn.line('.')
  if lnum ~= nil then
    lnum = lnum - 1
  else
    lnum = 0
  end
  return lnum
end

---@param bufnr integer
local function check_if_needs_formatting(bufnr)
  local formatting_clients = vim.lsp.get_clients({
    bufnr = bufnr,
    method = LspMethod.textDocument_formatting,
  })
  local formatting_params = vim.lsp.util.make_formatting_params()
  ---@type string[]
  local clients_needing_formatting = {}
  local clients_to_check = #formatting_clients
  local function on_format_needed()
    local lnum = get_current_lnum()
    ---@type Diagnostic
    local format_diagnostic = {
      bufnr = bufnr,
      col = vim.fn.col('.') or 0,
      lnum = lnum,
      message = 'Format needed from ' .. table.concat(clients_needing_formatting, ', '),
    }
    vim.diagnostic.set(format_diagnostic_namespace, bufnr, { format_diagnostic }, {})
  end
  for _, client in pairs(formatting_clients) do
    ---@param err any
    ---@param results lsp.TextEdit[]
    client.request(LspMethod.textDocument_formatting, formatting_params, function(err, results, _, _)
      if err then
        vim.notify('Error checking formatting: ' .. vim.inspect(err), vim.log.levels.ERROR)
      end
      for _, result in ipairs(results or {}) do
        local current_lines = vim.api.nvim_buf_get_lines(bufnr, result.range.start.line, result.range['end'].line, false)
        local formatted_lines = vim.split(string.gsub(result.newText, '\r\n?', '\n'), '\n', { plain = true })
        local formatted_lines_count = #formatted_lines
        if formatted_lines_count > 0 and formatted_lines[formatted_lines_count] == '' then
          formatted_lines_count = formatted_lines_count - 1
        end
        if #current_lines ~= formatted_lines_count then
          table.insert(clients_needing_formatting, client.name)
        else
          for i, line in ipairs(current_lines) do
            if line ~= formatted_lines[i] then
              table.insert(clients_needing_formatting, client.name)
              break
            end
          end
        end
        clients_to_check = clients_to_check - 1
        if clients_to_check == 0 then
          if #clients_needing_formatting > 0 then
            on_format_needed()
          else
            vim.diagnostic.reset(format_diagnostic_namespace, bufnr)
          end
        end
      end
    end, bufnr)
  end
end

local function update_formatting_diagnostic_position(bufnr)
  local current_diagnostics = vim.diagnostic.get(bufnr, { namespace = format_diagnostic_namespace })
  if #current_diagnostics ~= 1 then
    return
  end
  local lnum = get_current_lnum()
  local new_diagnostic = vim.deepcopy(current_diagnostics[1])
  new_diagnostic.lnum = lnum
  vim.diagnostic.set(format_diagnostic_namespace, bufnr, { new_diagnostic }, {})
end

---@param bufnr integer
function M.setup_formatting_diagnostic(bufnr)
  local existing_autocmds = vim.api.nvim_get_autocmds({ group = format_diagnostic_autocmd_group, buffer = bufnr })
  if #existing_autocmds > 0 then
    return
  end
  vim.api.nvim_create_autocmd({ 'TextChanged' }, {
    group = format_diagnostic_autocmd_group,
    buffer = bufnr,
    callback = function(args)
      check_if_needs_formatting(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
    group = format_diagnostic_autocmd_group,
    buffer = bufnr,
    callback = function(args)
      update_formatting_diagnostic_position(args.buf)
    end,
  })
end

return M
