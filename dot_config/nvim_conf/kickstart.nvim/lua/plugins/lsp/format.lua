LspMethod = vim.lsp.protocol.Methods

---@alias FormatCallback fun()

---@param bufnr integer
---@param ls_name string
---@param action_type string
---@param on_complete? FormatCallback
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
---@param on_complete? FormatCallback
local function format_go_imports(bufnr, on_complete)
  commit_code_action_edit(bufnr, 'gopls', 'source.organizeImports', on_complete)
end

---Fix all auto-fixable ruff lsp errors.
---@param bufnr integer
---@param on_complete? FormatCallback
local function fix_ruff_errors(bufnr, on_complete)
  commit_code_action_edit(bufnr, 'ruff_lsp', 'source.organizeImports', function()
    commit_code_action_edit(bufnr, 'ruff_lsp', 'source.fixAll', on_complete)
  end)
end

---Send batch code fixes to the typescript-tools language server.
---@param bufnr number
---@param on_complete? FormatCallback
local function apply_typescript_codefixes(bufnr, on_complete)
  local typescript_client = require('typescript-tools.utils').get_typescript_client(bufnr)
  if typescript_client == nil then
    if on_complete ~= nil then
      on_complete()
    end
    return
  end

  -- Reference: https://github.com/microsoft/TypeScript/blob/main/src/compiler/diagnosticMessages.json
  local error_codes = {
    -- Cannot find name '{0}'. Did you mean '{1}'?
    2552,
    -- Cannot find name '{0}'.
    2304,
    -- 'await' expressions are only allowed within async functions and at the top levels of modules.
    1308,
    -- Unreachable code detected.
    7027,
  }
  -- Reference: https://github.com/microsoft/TypeScript/tree/main/src/services/codefixes
  local fix_names = {
    'import',
    'fixAwaitInSyncFunction',
    'fixUnreachableCode',
  }

  local params = {
    diagnostics = vim.diagnostic.get(bufnr),
    bufnr = bufnr,
    error_codes = error_codes,
    fix_names = fix_names,
  }

  local lsp_constants = require('typescript-tools.protocol.constants')
  ---@param err lsp.ResponseError|nil
  ---@param res lsp.CodeAction
  typescript_client.request(lsp_constants.CustomMethods.BatchCodeActions, params, function(err, res)
    if err ~= nil then
      vim.notify('Error running typescript-tools code fixes: ' .. err.message, vim.log.levels.ERROR)
    else
      vim.lsp.util.apply_workspace_edit(res.edit, 'utf-8')
    end
    if on_complete ~= nil then
      on_complete()
    end
  end, bufnr)
end

---Remove unused imports from the current typescript file.
---@param bufnr integer
---@param on_complete? FormatCallback
local function remove_typescript_unused_imports(bufnr, on_complete)
  local lsp_constants = require('typescript-tools.protocol.constants')
  local params = { file = vim.api.nvim_buf_get_name(bufnr), mode = lsp_constants.OrganizeImportsMode.RemoveUnused }
  local typescript_client = require('typescript-tools.utils').get_typescript_client(bufnr)
  if typescript_client == nil then
    if on_complete ~= nil then
      on_complete()
    end
    return
  end

  typescript_client.request(lsp_constants.CustomMethods.OrganizeImports, params, function(err, res)
    if err ~= nil then
      vim.notify('Error running typescript-tools remove unused imports: ' .. err.message, vim.log.levels.ERROR)
    else
      vim.lsp.util.apply_workspace_edit(res, 'utf-8')
    end
    if on_complete ~= nil then
      on_complete()
    end
  end, bufnr)
end

---Fix all auto-fixable typescript errors.
---@param bufnr integer
---@param on_complete? FormatCallback
local function fix_typescript_errors(bufnr, on_complete)
  apply_typescript_codefixes(bufnr, function()
    remove_typescript_unused_imports(bufnr, on_complete)
  end)
end

---Perform async formatting on the current buffer.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? fun(clients_needing_formatting: string[]): nil
local function lsp_format(bufnr, dry_run, on_complete)
  local formatting_clients = vim.lsp.get_clients({
    bufnr = bufnr,
    method = LspMethod.textDocument_formatting,
  })
  local formatting_params = vim.lsp.util.make_formatting_params()
  ---@type string[]
  local clients_needing_formatting = {}
  local clients_to_check = #formatting_clients
  for _, client in pairs(formatting_clients) do
    ---@param err any
    ---@param results lsp.TextEdit[]
    client.request(LspMethod.textDocument_formatting, formatting_params, function(err, results, _, _)
      if err then
        if client.name ~= 'gopls' then
          vim.notify('Error checking formatting: ' .. vim.inspect(err), vim.log.levels.ERROR)
        end
      end
      if not dry_run then
        vim.lsp.util.apply_text_edits(results, bufnr, client.offset_encoding)
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
        if vim.tbl_contains(clients_needing_formatting, client.name) then
          break
        end
      end
      clients_to_check = clients_to_check - 1
      if clients_to_check == 0 then
        if on_complete ~= nil then
          on_complete(clients_needing_formatting)
        end
      end
    end, bufnr)
  end
end

local M = {}

---@param bufnr integer
function M.format(bufnr)
  -- TODO(@PeterPCardenas): Spawn a separate thread instead of using callbacks.
  format_go_imports(bufnr, function()
    fix_ruff_errors(bufnr, function()
      fix_typescript_errors(bufnr, function()
        local formatters = require('conform').list_formatters_for_buffer(bufnr)
        local index = 1

        local function format_next()
          if index > #formatters then
            lsp_format(bufnr, false)
            return
          end
          ---@type (string | string[])[]
          local formatter = {}
          table.insert(formatter, formatters[index])
          require('conform').format({
            formatter = formatter,
            async = true,
            lsp_fallback = false,
          }, function()
            index = index + 1
            format_next()
          end)
        end

        format_next()
      end)
    end)
  end)
end

local format_diagnostic_autocmd_group = vim.api.nvim_create_augroup('FormatChecker', { clear = true })
local format_diagnostic_namespace = vim.api.nvim_create_namespace('FormatChecker')

---@return integer
local function get_current_lnum()
  local lnum = vim.fn.line('.')
  if lnum ~= nil then
    -- Diagnostic lnums are 0-indexed, but vim.fn.line is 1-indexed.
    lnum = lnum - 1
  else
    lnum = 0
  end
  return lnum
end

---@param bufnr integer
local function check_if_needs_formatting(bufnr)
  ---Creates the formatting diagnostic if needed.
  ---@param clients_needing_formatting string[]
  local function on_format_needed(clients_needing_formatting)
    if #clients_needing_formatting == 0 then
      vim.diagnostic.reset(format_diagnostic_namespace, bufnr)
      return
    end
    local lnum = get_current_lnum()
    local col = vim.fn.col('.') or 0
    ---@type Diagnostic
    local format_diagnostic = {
      bufnr = bufnr,
      col = vim.fn.col('.') or 0,
      lnum = lnum,
      end_col = col,
      end_lnum = lnum,
      message = 'Format needed from ' .. table.concat(clients_needing_formatting, ', '),
    }
    vim.diagnostic.set(format_diagnostic_namespace, bufnr, { format_diagnostic }, {})
  end
  lsp_format(bufnr, true, on_format_needed)
end

local function update_formatting_diagnostic_position(bufnr)
  local current_diagnostics = vim.diagnostic.get(bufnr, { namespace = format_diagnostic_namespace })
  if #current_diagnostics ~= 1 then
    return
  end
  local lnum = get_current_lnum()
  local new_diagnostic = vim.deepcopy(current_diagnostics[1])
  new_diagnostic.lnum = lnum
  new_diagnostic.end_lnum = lnum
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
