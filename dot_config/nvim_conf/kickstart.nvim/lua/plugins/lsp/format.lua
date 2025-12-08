local LspMethod = vim.lsp.protocol.Methods
local Shell = require('utils.shell')
local Async = require('utils.async')
local File = require('utils.file')
local TypeScript = require('utils.typescript')
local Lsp = require('utils.lsp')

---Lock for buffers to hold while formatting.
---@type table<integer, boolean>
local format_lock_map = {}

---@param bufnr integer
local function lock_buffer(bufnr)
  format_lock_map[bufnr] = true
end

---@param bufnr integer
local function unlock_buffer(bufnr)
  format_lock_map[bufnr] = nil
end

---@param bufnr integer
local function is_buffer_locked(bufnr)
  return format_lock_map[bufnr] == true
end

---@type table<string, boolean>?
local ignored_formatters = nil
---@return table<string, boolean>
local function get_ignored_formatters()
  if ignored_formatters ~= nil then
    return ignored_formatters
  end
  local ignored_formatters_file = File.get_cwd() .. '/.formatignore'
  if vim.fn.filereadable(ignored_formatters_file) == 1 then
    local ignored_formatters_list = vim.tbl_filter(function(line) ---@param line string
      return line ~= ''
    end, vim.fn.readfile(ignored_formatters_file))
    ignored_formatters = {}
    if #ignored_formatters_list == 0 then
      ignored_formatters['all'] = true
    else
      for _, ignored_formatter in ipairs(ignored_formatters_list) do
        ignored_formatters[ignored_formatter] = true
      end
    end
  else
    ignored_formatters = {}
  end
  return ignored_formatters
end

---@alias FormatCallback fun(would_edit: boolean, did_cancel?: boolean): nil

---@param client vim.lsp.Client
local function get_client_offset_encoding(client)
  return (vim.lsp.get_client_by_id(client.id) or {}).offset_encoding or 'utf-16'
end

---@param bufnr integer
---@param edit lsp.TextEdit|lsp.AnnotatedTextEdit|lsp.SnippetTextEdit
local function edit_has_changes(bufnr, edit)
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, edit.range.start.line, edit.range['end'].line + 1, false)
  local formatted_lines = vim.split(string.gsub(edit.newText, '\r\n?', '\n'), '\n', { plain = true })
  local formatted_lines_count = #formatted_lines
  if
    formatted_lines_count > 0
    and formatted_lines[formatted_lines_count] == ''
    and edit.range['end'].line == edit.range.start.line
    and edit.range['end'].character == edit.range.start.character
  then
    formatted_lines_count = formatted_lines_count - 1
  end
  if #current_lines ~= formatted_lines_count then
    return true
  else
    for i, line in ipairs(current_lines) do
      if line ~= formatted_lines[i] then
        return true
      end
    end
  end
end

---Check if a code action has edits.
---@param bufnr number
---@param code_action lsp.CodeAction|lsp.WorkspaceEdit|nil
local function has_edits(bufnr, code_action)
  if code_action == nil then
    return false
  end
  local code_action_edit = code_action.edit or {}
  for _, change in ipairs(code_action_edit.documentChanges or {}) do
    if change.newUri ~= change.oldUri or change.kind then
      return true
    end
    for _, edit in ipairs(change.edits or {}) do
      if edit_has_changes(bufnr, edit) then
        return true
      end
    end
  end
  for _uri, edits in pairs(code_action_edit.changes or {}) do
    for _, edit in ipairs(edits) do
      if edit_has_changes(bufnr, edit) then
        return true
      end
    end
  end
  for _uri, edits in pairs(code_action.changes or {}) do
    for _, edit in ipairs(edits) do
      if edit_has_changes(bufnr, edit) then
        return true
      end
    end
  end
  return false
end

---@param bufnr integer
---@param ls_name string
---@param action_type lsp.CodeActionKind
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_from_code_action(bufnr, ls_name, action_type, dry_run, on_complete)
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
    ---@type lsp.CodeActionParams
    local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
    params.context = { only = { action_type }, diagnostics = {} }
    ---@param ls_results lsp.CodeAction[]
    client:request(LspMethod.textDocument_codeAction, params, function(err, ls_results, _ctx, _config)
      -- TODO: ruff is pretty noisy about errors
      if
        err
        and client.name ~= 'ruff_lsp'
        and (
          client.name ~= 'rust-analyzer'
          or (
            not vim.startswith(err.message, 'content modified')
            and not vim.startswith(err.message, 'file not found')
            and not vim.startswith(err.message, 'url is not a file')
          )
        )
      then
        vim.notify('Error running ' .. ls_name .. ' code action: ' .. vim.inspect(err), vim.log.levels.ERROR)
      end
      local did_edit = false
      for _, ls_result in ipairs(ls_results or {}) do
        if ls_result.edit then
          local offset_encoding = get_client_offset_encoding(client)
          local would_edit = has_edits(bufnr, ls_result)
          did_edit = did_edit or would_edit
          if not dry_run and would_edit then
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
  fix_from_code_action(bufnr, 'gopls', 'source.organizeImports', dry_run, on_complete)
end

---Fix all auto-fixable ruff lsp errors.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_ruff_errors(bufnr, dry_run, on_complete)
  fix_from_code_action(bufnr, 'ruff_lsp', 'source.organizeImports', dry_run, function()
    fix_from_code_action(bufnr, 'ruff_lsp', 'source.fixAll', dry_run, on_complete)
  end)
end

---Fix all auto-fixable rust_analyzer errors.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_rust_analyzer_errors(bufnr, dry_run, on_complete)
  fix_from_code_action(bufnr, 'rust-analyzer', 'source.organizeImports', dry_run, on_complete)
end

---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function auto_import_pyright(bufnr, dry_run, on_complete)
  ---@param would_edit boolean
  local function complete(would_edit)
    if on_complete ~= nil then
      on_complete(would_edit)
    end
  end
  if dry_run then
    complete(false)
    return
  end
  local pyright_client = vim.lsp.get_clients({ bufnr = bufnr, name = 'pyright' })[1]
  if pyright_client == nil then
    complete(false)
    return
  end
  local pyright_diags = vim.diagnostic.get(bufnr, { namespace = vim.lsp.diagnostic.get_namespace(pyright_client.id), severity = vim.diagnostic.severity.ERROR })
  ---@class DiagInfo
  ---@field completion_params lsp.TextDocumentPositionParams
  ---@field import_name string
  ---@field bufnr integer

  ---@type DiagInfo[]
  local diag_infos = {}
  ---@type table<string, boolean>
  local seen_import_names = {}
  for _, diag in ipairs(pyright_diags) do
    if diag.code == 'reportUndefinedVariable' then
      ---@type lsp.TextDocumentPositionParams
      local completion_params = {
        textDocument = vim.lsp.util.make_text_document_params(diag.bufnr),
        position = { line = diag.lnum, character = diag.end_col },
      }
      local unresolved_import = vim.api.nvim_buf_get_text(diag.bufnr, diag.lnum, diag.col, diag.end_lnum, diag.end_col, {})[1]
      if unresolved_import and not seen_import_names[unresolved_import] then
        seen_import_names[unresolved_import] = true
        ---@type DiagInfo
        local diag_info = { completion_params = completion_params, import_name = unresolved_import, bufnr = diag.bufnr }
        diag_infos[#diag_infos + 1] = diag_info
      end
    end
  end
  local current_index = 1
  local offset_encoding = get_client_offset_encoding(pyright_client)
  local would_edit = false
  local function auto_import_next()
    if current_index > #diag_infos then
      complete(would_edit)
      return
    end
    local diag_info = diag_infos[current_index]
    ---@param result vim.lsp.CompletionResult
    pyright_client:request(LspMethod.textDocument_completion, diag_info.completion_params, function(err, result, _context, _config)
      current_index = current_index + 1
      if err then
        auto_import_next()
        return
      end
      local completion_list = Lsp.completion_result_to_items(result)
      ---@type lsp.CompletionItem[]
      local auto_import_completions = {}
      for _, completion in ipairs(completion_list) do
        if
          completion.label == diag_info.import_name
          and completion.detail == 'Auto-import'
          and completion.additionalTextEdits
          and #completion.additionalTextEdits > 0
        then
          auto_import_completions[#auto_import_completions + 1] = completion
        end
      end
      if #auto_import_completions == 0 then
        auto_import_next()
        return
      end
      ---@param completion lsp.CompletionItem?
      local function auto_import(completion)
        if not completion then
          auto_import_next()
          return
        end
        would_edit = true
        vim.lsp.util.apply_text_edits(completion.additionalTextEdits, diag_info.bufnr, offset_encoding)
        auto_import_next()
      end
      local function pick_auto_import_completion(completions) ---@param completions lsp.CompletionItem[]
        if #completions == 1 then
          auto_import(completions[1])
          return
        end
        vim.ui.select(completions, {
          prompt = 'Select auto-import completion',
          ---@param completion lsp.CompletionItem
          format_item = function(completion)
            ---@type string?
            local module_name
            if completion.labelDetails and completion.labelDetails.description then
              module_name = completion.labelDetails.description
            end
            if module_name then
              return 'from ' .. module_name .. ' import ' .. completion.label
            end
            return 'import ' .. completion.label
          end,
        }, function(completion)
          auto_import(completion)
        end)
      end
      -- TODO: Can rather check to filter out non local imports when the completions include stdlib/external module imports by checking if the import maps to a file in project.
      Async.void(function() ---@async
        local success, output = Shell.async_cmd(
          'python',
          { '-c', "import sys; import importlib.util; print('" .. diag_info.import_name .. "' in getattr(sys, 'stdlib_module_names', []))" }
        )
        if not success or output[1] ~= 'True' then
          vim.schedule(function()
            pick_auto_import_completion(auto_import_completions)
          end)
          return
        end
        vim.schedule(function()
          ---@type lsp.CompletionItem[]
          local matching_completions = vim
            .iter(auto_import_completions)
            :filter(function(completion) ---@param completion lsp.CompletionItem
              return completion.label == diag_info.import_name and not completion.labelDetails
            end)
            :totable()
          if #matching_completions > 0 then
            pick_auto_import_completion(matching_completions)
            return
          end
          vim.notify('Could not find stdlib auto-import completion for ' .. diag_info.import_name, vim.log.levels.ERROR)
          pick_auto_import_completion(auto_import_completions)
        end)
      end)
    end, diag_info.bufnr)
  end
  auto_import_next()
end

---@class BatchCodeActionParams
---@field diagnostics vim.Diagnostic[]
---@field bufnr integer
---@field error_codes integer[]
---@field fix_names string[]

---Send batch code fixes to the typescript-tools language server.
---@param bufnr number
---@param dry_run boolean
---@param on_complete? FormatCallback
local function apply_typescript_codefixes(bufnr, dry_run, on_complete)
  ---@type vim.lsp.Client|nil
  ---@diagnostic disable-next-line: assign-type-mismatch
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
    -- '{0}' cannot be used as a value because it was imported using 'import type'.
    1361,
    -- Unreachable code detected.
    7027,
    -- '{0}' refers to a UMD global, but the current file is a module. Consider adding an import instead.
    2686,
    -- Non-abstract class '{0}' is missing implementations for the following members of '{1}': {2}.
    2654,
    -- Non-abstract class '{0}' does not implement inherited abstract member {1} from class '{2}'.
    2515,
  }
  -- Reference: https://github.com/microsoft/TypeScript/tree/main/src/services/codefixes
  local fix_names = {
    'import',
    'fixAwaitInSyncFunction',
    'fixUnreachableCode',
    'fixClassDoesntImplementInheritedAbstractMember',
  }

  ---@type BatchCodeActionParams
  local params = {
    diagnostics = vim.diagnostic.get(bufnr),
    bufnr = bufnr,
    error_codes = error_codes,
    fix_names = fix_names,
  }

  local did_finish = false
  -- vim.defer_fn(function()
  --   if not did_finish then
  --     vim.notify('Timed out waiting for typescript-tools to respond', vim.log.levels.ERROR)
  --     if on_complete ~= nil then
  --       on_complete(false, true)
  --     end
  --   end
  --   did_finish = true
  -- end, 1000)

  local lsp_constants = require('typescript-tools.protocol.constants')
  ---@param err lsp.ResponseError|nil
  ---@param res lsp.CodeAction
  typescript_client:request(lsp_constants.CustomMethods.BatchCodeActions, params, function(err, res)
    if did_finish then
      return
    end
    local did_edit = false
    if err ~= nil then
      vim.notify('Error running typescript-tools code fixes: ' .. err.message, vim.log.levels.ERROR)
    else
      did_edit = has_edits(bufnr, res)
      if not dry_run and did_edit then
        vim.lsp.util.apply_workspace_edit(res.edit, 'utf-8')
      end
    end
    did_finish = true
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
  ---@type vim.lsp.Client|nil
  ---@diagnostic disable-next-line: assign-type-mismatch
  local typescript_client = require('typescript-tools.utils').get_typescript_client(bufnr)
  if typescript_client == nil then
    if on_complete ~= nil then
      on_complete(false)
    end
    return
  end

  typescript_client:request(lsp_constants.CustomMethods.OrganizeImports, params, function(err, res)
    local did_edit = false
    if err ~= nil then
      vim.notify('Error running typescript-tools remove unused imports: ' .. err.message, vim.log.levels.ERROR)
    else
      did_edit = has_edits(bufnr, res)
      if not dry_run and did_edit then
        vim.lsp.util.apply_workspace_edit(res, 'utf-8')
      end
    end
    if on_complete ~= nil then
      on_complete(did_edit)
    end
  end, bufnr)
end

---Fix all auto-fixable typescript errors.
---@param bufnr integer
---@param dry_run boolean
---@param on_complete? FormatCallback
local function fix_typescript_errors(bufnr, dry_run, on_complete)
  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  if not vim.tbl_contains(TypeScript.SUPPORTED_FT, filetype) then
    if on_complete ~= nil then
      on_complete(false)
    end
    return
  end
  -- Don't run formatting in dry run mode.
  -- TODO: possibly re-enable when debounced.
  if dry_run then
    if on_complete ~= nil then
      on_complete(false)
    end
    return
  end
  apply_typescript_codefixes(bufnr, dry_run, function(would_edit_from_codefix, did_cancel)
    -- Exit early when cancelled.
    -- TODO: Make formatting more robust so that it doesn't timeout.
    if did_cancel then
      if on_complete ~= nil then
        on_complete(false, true)
      end
      return
    end
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
    -- TODO: Only disable formatter when a client has timed out once before on this buffer.
    if get_ignored_formatters()[client.name] or (dry_run and client.name == 'eslint') then
      clients_to_check = clients_to_check - 1
      if clients_to_check == 0 then
        if on_complete ~= nil then
          on_complete(clients_needing_formatting)
        end
      end
    else
      ---@param err any
      ---@param results lsp.TextEdit[]
      client:request(LspMethod.textDocument_formatting, formatting_params, function(err, results, _, _)
        if err then
          if
            client.name ~= 'gopls'
            and client.name ~= 'ruff_lsp'
            and (
              client.name ~= 'rust-analyzer'
              or (
                not vim.startswith(err.message, 'file not found')
                and not vim.startswith(err.message, 'content modified')
                and not vim.startswith(err.message, 'url is not a file')
              )
            )
          then
            vim.notify('Error checking formatting: ' .. vim.inspect(err), vim.log.levels.ERROR)
          end
        end
        if not dry_run and results ~= nil then
          local offset_encoding = get_client_offset_encoding(client)
          vim.lsp.util.apply_text_edits(results, bufnr, offset_encoding)
        end
        for _, result in ipairs(results or {}) do
          local has_changes = edit_has_changes(bufnr, result)
          if has_changes then
            clients_needing_formatting[#clients_needing_formatting + 1] = client.name
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
end

---Check if the current buffer needs auto-fixing.
---@param bufnr integer
---@param dry_run boolean If true, no edits will be made.
---@param on_complete? fun(sources_with_formatting: string[]): nil
local function format_with_check(bufnr, dry_run, on_complete)
  ---@type string[]
  local sources_with_edits = {}
  ---@type { [1]: string, [2]: fun(bufnr: integer, dry_run: boolean, on_complete: FormatCallback): nil }[]
  local autofixers = {
    { 'gopls', format_go_imports },
    { 'pyright', auto_import_pyright },
    { 'ruff_lsp', fix_ruff_errors },
    { 'typescript-tools', fix_typescript_errors },
    { 'rust-analyzer', fix_rust_analyzer_errors },
  }

  local possible_formatter_names = require('conform').list_formatters_for_buffer(bufnr)
  local formatters = require('conform').resolve_formatters(possible_formatter_names, bufnr, not dry_run, false)
  local formatter_index = 1
  local autofixer_index = 1

  local function format_next()
    if autofixer_index <= #autofixers then
      local autofixer_pair = autofixers[autofixer_index]
      local autofixer_name, autofix_fn = autofixer_pair[1], autofixer_pair[2]
      if get_ignored_formatters()[autofixer_name] then
        autofixer_index = autofixer_index + 1
        format_next()
        return
      end
      autofix_fn(bufnr, dry_run, function(would_edit_from_autofixer)
        if would_edit_from_autofixer then
          sources_with_edits[#sources_with_edits + 1] = autofixer_name
        end
        autofixer_index = autofixer_index + 1
        format_next()
      end)
      return
    elseif formatter_index > #formatters then
      lsp_format(bufnr, dry_run, function(clients_that_would_format)
        for _, client in ipairs(clients_that_would_format) do
          sources_with_edits[#sources_with_edits + 1] = client
        end
        if on_complete ~= nil then
          on_complete(sources_with_edits)
        end
      end)
      return
    end
    local formatter_name = formatters[formatter_index].name
    if get_ignored_formatters()[formatter_name] then
      formatter_index = formatter_index + 1
      format_next()
      return
    end
    require('conform').format({
      formatters = { formatter_name },
      async = true,
      dry_run = dry_run,
      quiet = dry_run,
      lsp_format = 'never',
    }, function(_err, would_edit_from_formatter)
      if would_edit_from_formatter then
        sources_with_edits[#sources_with_edits + 1] = formatter_name
      end
      formatter_index = formatter_index + 1
      format_next()
    end)
  end

  format_next()
end

local M = {}

M.format_diagnostic_autocmd_group = vim.api.nvim_create_augroup('FormatChecker', { clear = true })
M.format_diagnostic_namespace = vim.api.nvim_create_namespace('FormatChecker')

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
    vim.diagnostic.reset(M.format_diagnostic_namespace, bufnr)
    return
  end
  local lnum = get_current_lnum()
  local col = vim.fn.col('.') or 0
  ---@type vim.Diagnostic
  local format_diagnostic = {
    bufnr = bufnr,
    col = vim.fn.col('.') or 0,
    lnum = lnum,
    end_col = col,
    end_lnum = lnum,
    message = 'Format needed from ' .. table.concat(sources_needing_formatting, ', '),
  }
  vim.diagnostic.set(M.format_diagnostic_namespace, bufnr, { format_diagnostic }, {})
end

local queued_format_checks = {} ---@type table<integer, boolean>

---@param bufnr integer
local function check_if_needs_formatting(bufnr)
  if is_buffer_locked(bufnr) then
    return
  end
  -- Conform doesn't behave well when isssuing multiple format requests at once.
  -- So we debounce to only ever have one format check at a time.
  if queued_format_checks[bufnr] == true then
    return
  end
  if queued_format_checks[bufnr] == nil then
    queued_format_checks[bufnr] = false
  else
    queued_format_checks[bufnr] = true
    return
  end

  format_with_check(bufnr, true, function(sources_needing_formatting)
    update_format_diagnostic(bufnr, sources_needing_formatting)
    local has_queued_format_check = queued_format_checks[bufnr]
    queued_format_checks[bufnr] = nil
    if has_queued_format_check then
      check_if_needs_formatting(bufnr)
    end
  end)
end

local function update_formatting_diagnostic_position(bufnr)
  local current_diagnostics = vim.diagnostic.get(bufnr, { namespace = M.format_diagnostic_namespace })
  if #current_diagnostics ~= 1 then
    return
  end
  local lnum = get_current_lnum()
  local new_diagnostic = vim.deepcopy(current_diagnostics[1])
  new_diagnostic.lnum = lnum
  new_diagnostic.end_lnum = lnum
  vim.diagnostic.set(M.format_diagnostic_namespace, bufnr, { new_diagnostic }, {})
end

-- TODO: Add diagnostics where formatting would be applied (similar to eslint-plugin-prettier) and move the following diagnostic to fidget
---@param bufnr integer
function M.setup_formatting_diagnostic(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if not File.file_exists(filename) then
    return
  end
  -- Format check is slow for large typescript files, so disable them for now.
  local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
  local is_typescript = vim.tbl_contains(TypeScript.SUPPORTED_FT, filetype)
  if vim.api.nvim_buf_line_count(bufnr) > 600 and is_typescript then
    return
  end
  local git_root_dir = File.get_git_root()
  --- Disable format checking when there's no git root or the file is not in the git root.
  if filetype ~= 'gitcommit' and (git_root_dir == nil or not File.file_in_directory(filename, git_root_dir)) then
    return
  end
  Async.void(
    ---@async
    function()
      local success, _ = Shell.async_cmd('git', { 'check-ignore', '--quiet', filename })
      if success then
        return
      end
      vim.schedule(function()
        -- In the time of checking if we should format, the buffer might have been deleted/otherwise made invalid.
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        -- Check if the buffer needs formatting on enter.
        check_if_needs_formatting(bufnr)
        -- Check if the buffer needs formatting on text change while in normal mode, or after leaving insert mode.
        -- TODO: Ideally we would only check when changes have actually been made.
        vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
          group = M.format_diagnostic_autocmd_group,
          buffer = bufnr,
          callback = function(args)
            check_if_needs_formatting(args.buf)
          end,
        })
        vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
          group = M.format_diagnostic_autocmd_group,
          buffer = bufnr,
          callback = function(args)
            update_formatting_diagnostic_position(args.buf)
          end,
        })
      end)
    end
  )
end

-- TODO: Add user command to force enable formatting.

---@param bufnr integer
function M.format(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if not File.file_exists(filename) then
    return
  end
  local git_root_dir = File.get_git_root()
  if vim.bo[bufnr].filetype ~= 'gitcommit' and (git_root_dir == nil or not File.file_in_directory(filename, git_root_dir)) then
    vim.notify('Cannot format files outside of the git root', vim.log.levels.ERROR)
    return
  end
  lock_buffer(bufnr)
  format_with_check(bufnr, false, function(_)
    unlock_buffer(bufnr)
    check_if_needs_formatting(bufnr)
  end)
end

return M
