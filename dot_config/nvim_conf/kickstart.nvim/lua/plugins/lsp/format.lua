LspMethod = vim.lsp.protocol.Methods

---@alias FormatCallback fun(would_edit: boolean): nil

---@param client lsp.Client
local function get_client_offset_encoding(client)
  return (vim.lsp.get_client_by_id(client.id) or {}).offset_encoding or 'utf-16'
end

---Check if a code action has edits.
---@param bufnr number
---@param code_action lsp.CodeAction|nil
local function has_edits(bufnr, code_action)
  if code_action == nil then
    return false
  end
  if not vim.tbl_isempty(code_action.edit or {}) then
    return false
  end
  for _, change in ipairs(code_action.edit.documentChanges or {}) do
    if change.newUri ~= change.oldUri or not vim.tbl_isempty(change.edits) then
      return true
    end
  end
  for uri, change in pairs(code_action.edit.changes or {}) do
    if not vim.tbl_isempty(change) then
      return true
    end
  end
  return false
end

---@param bufnr integer
---@param ls_name string
---@param action_type lsp.CodeActionKind
---@param dry_run boolean
---@param on_complete? FormatCallback
local function commit_code_action_edit(bufnr, ls_name, action_type, dry_run, on_complete)
  ---@type lsp.CodeActionParams
  local params = vim.lsp.util.make_range_params()
  params.context = { only = { action_type }, diagnostics = {} }
  local clients = vim.lsp.get_clients({
    bufnr = bufnr,
    name = ls_name,
    method = LspMethod.textDocument_codeAction,
  })
  if #clients == 0 then
    if on_complete then
      on_complete(false)
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
      local did_edit = false
      for _, ls_result in ipairs(ls_results or {}) do
        if ls_result.edit then
          local offset_encoding = get_client_offset_encoding(client)
          did_edit = did_edit or has_edits(bufnr, ls_result)
          if not dry_run then
            vim.lsp.util.apply_workspace_edit(ls_result.edit, offset_encoding)
          end
        end
      end
      completion_count = completion_count + 1
      if completion_count == #clients and on_complete then
        on_complete(did_edit)
      end
    end, bufnr)
  end
end

---Organizes go imports.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function format_go_imports(bufnr, dry_run, on_complete)
  commit_code_action_edit(bufnr, 'gopls', 'source.organizeImports', dry_run, on_complete)
end

---Fix all auto-fixable ruff lsp errors.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_ruff_errors(bufnr, dry_run, on_complete)
  commit_code_action_edit(bufnr, 'ruff_lsp', 'source.organizeImports', dry_run, function()
    commit_code_action_edit(bufnr, 'ruff_lsp', 'source.fixAll', dry_run, on_complete)
  end)
end

---@class BatchCodeActionParams
---@field diagnostics Diagnostic[]
---@field bufnr integer
---@field error_codes integer[]
---@field fix_names string[]

---Send batch code fixes to the typescript-tools language server.
---@param bufnr number
---@param dry_run boolean
---@param on_complete? FormatCallback
local function apply_typescript_codefixes(bufnr, dry_run, on_complete)
  local typescript_client = require('typescript-tools.utils').get_typescript_client(bufnr)
  if typescript_client == nil then
    if on_complete ~= nil then
      on_complete(false)
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

  ---@type BatchCodeActionParams
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
    local did_edit = false
    if err ~= nil then
      vim.notify('Error running typescript-tools code fixes: ' .. err.message, vim.log.levels.ERROR)
    else
      did_edit = has_edits(bufnr, res)
      if not dry_run then
        vim.lsp.util.apply_workspace_edit(res.edit, 'utf-8')
      end
    end
    if on_complete ~= nil then
      on_complete(did_edit)
    end
  end, bufnr)
end

---@class OrganizeImportsParams
---@field file string
---@field mode OrganizeImportsMode

---Remove unused imports from the current typescript file.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function remove_typescript_unused_imports(bufnr, dry_run, on_complete)
  local lsp_constants = require('typescript-tools.protocol.constants')
  ---@type OrganizeImportsParams
  local params = { file = vim.api.nvim_buf_get_name(bufnr), mode = lsp_constants.OrganizeImportsMode.RemoveUnused }
  local typescript_client = require('typescript-tools.utils').get_typescript_client(bufnr)
  if typescript_client == nil then
    if on_complete ~= nil then
      on_complete(false)
    end
    return
  end

  typescript_client.request(lsp_constants.CustomMethods.OrganizeImports, params, function(err, res)
    if err ~= nil then
      vim.notify('Error running typescript-tools remove unused imports: ' .. err.message, vim.log.levels.ERROR)
    else
      if not dry_run then
        vim.lsp.util.apply_workspace_edit(res, 'utf-8')
      end
    end
    if on_complete ~= nil then
      -- TODO: The edit is the same as the content but is very weird. It replaces the first line with the same lines and the lines that exist
      -- below it, and then removes the lines it replaces in another edit. This is a bug in the typescript-tools server.
      on_complete(false)
    end
  end, bufnr)
end

---Fix all auto-fixable typescript errors.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_typescript_errors(bufnr, dry_run, on_complete)
  apply_typescript_codefixes(bufnr, dry_run, function(would_edit_from_codefix)
    remove_typescript_unused_imports(bufnr, dry_run, function(would_edit_from_remove_unused)
      if on_complete ~= nil then
        on_complete(would_edit_from_codefix or would_edit_from_remove_unused)
      end
    end)
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
  if clients_to_check == 0 then
    if on_complete ~= nil then
      on_complete(clients_needing_formatting)
    end
    return
  end
  for _, client in ipairs(formatting_clients) do
    ---@param err any
    ---@param results lsp.TextEdit[]
    client.request(LspMethod.textDocument_formatting, formatting_params, function(err, results, _, _)
      if err then
        if client.name ~= 'gopls' then
          vim.notify('Error checking formatting: ' .. vim.inspect(err), vim.log.levels.ERROR)
        end
      end
      if not dry_run and results ~= nil then
        local offset_encoding = get_client_offset_encoding(client)
        vim.lsp.util.apply_text_edits(results, bufnr, offset_encoding)
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

---Check if the current buffer needs auto-fixing.
---@param bufnr integer
---@param dry_run boolean If true, no edits will be made.
---@param on_complete? fun(sources_with_formatting: string[]): nil
local function format_with_check(bufnr, dry_run, on_complete)
  ---@type string[]
  local sources_with_edits = {}

  -- TODO(@PeterPCardenas): Spawn a separate thread instead of using callbacks.
  format_go_imports(bufnr, dry_run, function(would_edit_from_go_imports)
    if would_edit_from_go_imports then
      table.insert(sources_with_edits, 'gopls')
    end
    fix_ruff_errors(bufnr, dry_run, function(would_edit_from_ruff_errors)
      if would_edit_from_ruff_errors then
        table.insert(sources_with_edits, 'ruff_lsp')
      end
      fix_typescript_errors(bufnr, dry_run, function(would_edit_from_typescript_errors)
        if would_edit_from_typescript_errors then
          table.insert(sources_with_edits, 'typescript-tools')
        end
        local possible_formatter_names = require('conform').list_formatters_for_buffer(bufnr)
        local formatters = require('conform').resolve_formatters(possible_formatter_names, bufnr, not dry_run)
        local index = 1

        local function format_next()
          if index > #formatters then
            lsp_format(bufnr, dry_run, function(clients_that_would_format)
              for _, client in ipairs(clients_that_would_format) do
                table.insert(sources_with_edits, client)
              end
              if on_complete ~= nil then
                on_complete(sources_with_edits)
              end
            end)
            return
          end
          local formatter_name = formatters[index].name
          require('conform').format({
            formatters = { formatter_name },
            async = true,
            dry_run = dry_run,
            quiet = dry_run,
            lsp_fallback = false,
          }, function(_, would_edit_from_formatter)
            if would_edit_from_formatter then
              table.insert(sources_with_edits, formatter_name)
            end
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

---Creates the formatting diagnostic if needed.
---@param bufnr integer
---@param sources_needing_formatting string[]
local function update_format_diagnostic(bufnr, sources_needing_formatting)
  if #sources_needing_formatting == 0 then
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
    message = 'Format needed from ' .. table.concat(sources_needing_formatting, ', '),
  }
  vim.diagnostic.set(format_diagnostic_namespace, bufnr, { format_diagnostic }, {})
end

---@param bufnr integer
local function check_if_needs_formatting(bufnr)
  format_with_check(bufnr, true, function(sources_needing_formatting)
    update_format_diagnostic(bufnr, sources_needing_formatting)
  end)
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

local M = {}

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

---@param bufnr integer
function M.format(bufnr)
  format_with_check(bufnr, false, function(sources_needing_formatting)
    update_format_diagnostic(bufnr, sources_needing_formatting)
  end)
end

return M
