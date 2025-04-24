local Async = require('utils.async')
local File = require('utils.file')
local Format = require('plugins.lsp.format')
local Shell = require('utils.shell')
local Python = require('plugins.lsp.python')

local LINT_POLL_INTERVAL_MS = 500
local lint_poll_timer = nil

local function update_lint_notification()
  local running_linters = require('lint').get_running()
  if #running_linters > 0 then
    require('fidget').notify('Running ' .. table.concat(running_linters, ', ') .. '...', vim.log.levels.INFO, {
      group = 'lint_status',
      key = 'lint_status',
      annote = '',
    })
  else
    require('fidget').notification.remove('lint_status', 'lint_status')
  end
end

---@type table<string, integer>
local filename_to_last_edited = {}

---@param bufnr integer
local function update_lint_configs_for_buf(bufnr)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].filetype ~= 'python' then
    return
  end
  local lsp_root = Python.find_lsp_root(filepath)
  if not lsp_root then
    return
  end
  local pylint_cmd = lsp_root .. '/venv/bin/pylint'
  if vim.fn.executable(pylint_cmd) == 1 then
    require('lint').linters.pylint.cmd = lsp_root .. '/venv/bin/pylint'
    require('lint').linters.pylint.env = {
      VIRTUAL_ENV = lsp_root .. '/venv',
      PYTHONPATH = lsp_root .. ':' .. lsp_root .. '/' .. Python.GEN_FILES_PATH,
    }
  end
  local dmypy_cmd = lsp_root .. '/venv/bin/dmypy'
  if vim.fn.executable(dmypy_cmd) == 1 then
    require('lint').linters.dmypy.cmd = lsp_root .. '/venv/bin/dmypy'
    require('lint').linters.dmypy.env = {
      VIRTUAL_ENV = lsp_root .. '/venv',
      COLUMNS = 1000,
      MYPYPATH = lsp_root .. ':' .. lsp_root .. '/' .. Python.GEN_FILES_PATH,
    }
  end
end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter', 'BufNewFile' }, {
  desc = 'Lint on write',
  group = vim.api.nvim_create_augroup('LintOnWrite', { clear = true }),
  callback = function(opts)
    local bufnr = opts.buf
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    -- Don't lint if the file wasn't edited.
    local last_edited = vim.fn.getftime(bufname)
    if filename_to_last_edited[bufname] then
      local tracked_last_edit = filename_to_last_edited[bufname]
      if tracked_last_edit == last_edited then
        return
      end
    end
    filename_to_last_edited[bufname] = last_edited
    update_lint_configs_for_buf(bufnr)
    require('lint').try_lint()

    -- Start polling timer if not already running
    if not lint_poll_timer then
      lint_poll_timer = vim.loop.new_timer()
      lint_poll_timer:start(
        0,
        LINT_POLL_INTERVAL_MS,
        vim.schedule_wrap(function()
          update_lint_notification()

          -- Stop timer if no linters running
          if #require('lint').get_running() == 0 then
            if lint_poll_timer then
              lint_poll_timer:stop()
              lint_poll_timer = nil
            end
          end
        end)
      )
    end
  end,
})

local nogo_diagnostic_ns = vim.api.nvim_create_namespace('GoBazelLint')

---Map of filenames to functions that will lint the file.
---@type table<string, async fun(): nil>
local bazel_go_lint_queue = {}

---@async
local function enqueue_next_bazel_go_lint()
  local filename, exec = next(bazel_go_lint_queue)
  if filename then
    bazel_go_lint_queue[filename] = nil
    if not exec then
      vim.schedule(function()
        vim.notify('Failed to lint file with bazel-go-build', vim.log.levels.ERROR)
      end)
      return
    end
    exec()
  end
end

---@async
---@param abs_filepath string
local function bazel_go_lint(abs_filepath)
  local workspace_root = File.get_ancestor_dir('WORKSPACE')
  if not workspace_root then
    enqueue_next_bazel_go_lint()
    return
  end
  local output_base_id = workspace_root:gsub('/', '_')
  local output_base_flag = string.format('--output_base=$HOME/.cache/bazel/_bazel_go_build_lint_%s', output_base_id)
  local relative_filepath = string.sub(abs_filepath, #workspace_root + 2)
  local current_filename = vim.fn.fnamemodify(abs_filepath, ':t')
  local relative_parent_dir = string.sub(relative_filepath, 1, string.len(relative_filepath) - string.len(current_filename) - 1)
  local query_targets = string.format('kind(go_*, rdeps(//%s/..., %s, 1))', relative_parent_dir, relative_filepath)
  success, output = Shell.async_cmd('fish', { '-c', string.format('bazel %s query --color=no "%s"', output_base_flag, query_targets) })
  if not success then
    vim.schedule(function()
      vim.notify('Failed to bazel query for go', vim.log.levels.ERROR)
    end)
    enqueue_next_bazel_go_lint()
    return
  end
  ---@type string[]
  local matched_targets = {}
  for _, line in ipairs(output) do
    -- TODO: Make regex more robust.
    local target = string.match(line, '//[a-zA-Z_:/]+$')
    if target then
      matched_targets[#matched_targets + 1] = target
    end
  end

  success, output = Shell.async_cmd(
    'fish',
    { '-c', string.format('bazel %s build --unified_protos=false --config=dev --color=no %s', output_base_flag, table.concat(matched_targets, ' ')) }
  )
  ---@type table<string, lsp.Diagnostic[]>
  local file_diagnostics = {}
  ---@param line string
  local function parse_line(line)
    local filename, line_num_str, col_num_str, error_msg = string.match(line, '^(%S+):(%d+):(%d+): (.+)$')
    if not filename then
      return
    end
    local line_num, col_num = tonumber(line_num_str), tonumber(col_num_str)
    if line_num == nil or col_num == nil then
      return
    end
    ---@type vim.Diagnostic
    local diagnostic = {
      source = 'bazel-go-build',
      message = error_msg,
      range = {
        start = { line = line_num - 1, character = col_num - 1 },
        ['end'] = { line = line_num - 1, character = col_num - 1 },
      },
      severity = vim.diagnostic.severity.ERROR,
      lnum = line_num - 1,
      col = col_num - 1,
    }
    if not file_diagnostics[filename] then
      file_diagnostics[filename] = {}
    end
    file_diagnostics[filename][#file_diagnostics[filename] + 1] = diagnostic
  end
  for _, line in ipairs(output) do
    parse_line(line)
  end
  local function filename_to_bufnr(filename)
    local file_uri = vim.uri_from_fname(workspace_root .. '/' .. filename)
    local bufnr = vim.uri_to_bufnr(file_uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end
    vim.bo[bufnr].buflisted = true
    return bufnr
  end

  local function set_diagnostics()
    vim.diagnostic.reset(nogo_diagnostic_ns)
    for filename, diagnostics in pairs(file_diagnostics) do
      local bufnr = filename_to_bufnr(filename)
      vim.diagnostic.set(nogo_diagnostic_ns, bufnr, diagnostics, { underline = true })
      Async.void(
        ---@async
        function()
          enqueue_next_bazel_go_lint()
        end
      )
    end
  end
  vim.schedule(set_diagnostics)
end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter' }, {
  desc = 'Lint from bazel build output on write',
  group = vim.api.nvim_create_augroup('GoBazelLint', { clear = true }),
  pattern = '*.go',
  callback = function()
    local abs_filepath = vim.fn.expand('%:p')
    if type(abs_filepath) ~= 'string' then
      return
    end
    if #bazel_go_lint_queue == 0 then
      Async.void(
        ---@async
        function()
          bazel_go_lint(abs_filepath)
        end
      )
    end
    bazel_go_lint_queue[abs_filepath] =
      ---@async
      function()
        bazel_go_lint(abs_filepath)
      end
  end,
})

---@param bufnr number
local function get_buildifier_filetype(bufnr)
  -- Logic taken from https://github.com/bazelbuild/buildtools/blob/master/build/lex.go#L125
  bufnr = bufnr or 0
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
  fname = string.lower(fname)

  if fname == 'module.bazel' then
    return 'module'
  elseif vim.endswith(fname, '.bzl') then
    return 'bzl'
  elseif vim.endswith(fname, '.sky') then
    return 'default'
  elseif fname == 'build' or vim.startswith(fname, 'build.') or vim.endswith(fname, '.build') then
    return 'build'
  elseif fname == 'workspace' or vim.startswith(fname, 'workspace.') or vim.endswith(fname, '.workspace') then
    return 'workspace'
  else
    return 'default'
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufRead', 'BufNewFile' }, {
  desc = 'Setup formatting',
  callback = function(args)
    ---@type number
    local bufnr = args.buf
    vim.keymap.set({ 'n', 'v' }, '<leader>lf', function()
      Format.format(bufnr)
    end, {
      desc = 'Format buffer',
      buffer = bufnr,
    })
    Format.setup_formatting_diagnostic(bufnr)
  end,
})

local function get_buildifier_warnings_arg()
  -- Buildifier warnings in 7.3.1
  local buildifier_warnings = {
    'attr-applicable_licenses',
    'attr-cfg',
    'attr-license',
    'attr-licenses',
    'attr-non-empty',
    'attr-output-default',
    'attr-single-file',
    'build-args-kwargs',
    'bzl-visibility',
    'confusing-name',
    'constant-glob',
    'ctx-actions',
    'ctx-args',
    'deprecated-function',
    'depset-items',
    'depset-iteration',
    'depset-union',
    'dict-concatenation',
    'dict-method-named-arg',
    'duplicated-name',
    'filetype',
    'function-docstring',
    'function-docstring-args',
    'function-docstring-header',
    'function-docstring-return',
    'git-repository',
    'http-archive',
    'integer-division',
    'keyword-positional-params',
    'list-append',
    'load',
    'module-docstring',
    'name-conventions',
    'native-android',
    'native-build',
    'native-cc',
    'native-java',
    'native-package',
    'native-proto',
    'native-py',
    'no-effect',
    'output-group',
    'overly-nested-depset',
    'package-name',
    'package-on-top',
    'positional-args',
    'print',
    'provider-params',
    'redefined-variable',
    'repository-name',
    'return-value',
    'rule-impl-return',
    'skylark-comment',
    'skylark-docstring',
    'string-iteration',
    'uninitialized',
    'unnamed-macro',
    'unreachable',
    'unsorted-dict-items',
    'unused-variable',
  }
  local ignored_buildifier_warnings = {
    ['native-cc'] = true,
    ['native-proto'] = true,
    ['native-py'] = true,
    ['native-java'] = true,
  }
  ---@type string[]
  local filtered_buildifier_warnings = vim.tbl_filter(function(warning) ---@param warning string
    return ignored_buildifier_warnings[warning] == nil
  end, buildifier_warnings)
  local buildifier_warnings_arg = '--warnings=' .. table.concat(filtered_buildifier_warnings, ',')
  return buildifier_warnings_arg
end

---@type LazyPluginSpec[]
return {
  -- Formatting.
  {
    'stevearc/conform.nvim',
    lazy = true,
    config = function()

      local buildifier_warnings_arg = get_buildifier_warnings_arg()
      require('conform').setup({
        formatters_by_ft = {
          lua = { 'stylua' },
          go = { 'golines' },
          bzl = { 'buildifier' },
          json = function(bufnr)
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            if vim.endswith(bufname, 'lazy-lock.json') then
              return {}
            end
            return { 'jq' }
          end,
          jsonc = { 'jq' },
          fish = { 'fish_indent' },
          sh = { 'shfmt' },
          gitcommit = { 'commitmsgfmt' },
          proto = { 'clang-format' },
        },
        formatters = {
          buildifier = {
            ---@type fun(self: conform.JobFormatterConfig, ctx: conform.Context): string|string[]
            args = function(_, ctx)
              local filetype = get_buildifier_filetype(ctx.buf)
              return { '-lint=fix', buildifier_warnings_arg, '-type', filetype }
            end,
          },
          golines = {
            args = { '--no-reformat-tags' },
          },
        },
        notify_on_error = true,
      })
    end,
  },

  -- Diagnostics from lint tools.
  {
    'mfussenegger/nvim-lint',
    lazy = true,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('lint').linters.golint = {
        name = 'golint',
        cmd = 'golint',
        stdin = false,
        ignore_exitcode = true,
        parser = require('lint.parser').from_pattern(
          '([^:]+):([0-9]+):([0-9]+): (.+)',
          { 'filename', 'lnum', 'col', 'message' },
          {},
          { severity = vim.diagnostic.severity.WARN }
        ),
      }
      local buf_lint_args = { 'lint', '--error-format', 'json' }
      local cwd = File.get_cwd()
      local buf_config_path = cwd .. '/buf.yaml'
      buf_lint_args[#buf_lint_args + 1] = '--config'
      buf_lint_args[#buf_lint_args + 1] = buf_config_path
      buf_lint_args[#buf_lint_args + 1] = '--path'
      require('lint').linters.buf_lint.args = buf_lint_args
      require('lint').linters.buf_lint.cwd = cwd
      local mypypath = table.concat({ cwd, cwd .. '/' .. Python.GEN_FILES_PATH }, ':')
      require('lint').linters.dmypy.env = {
        COLUMNS = 1000,
        MYPYPATH = mypypath,
      }
      local original_mypy_parser = require('lint').linters.dmypy.parser
      require('lint').linters.dmypy.parser = function(output, bufnr, linter_cwd)
        local diagnostics = original_mypy_parser(output, bufnr, linter_cwd)
        ---@type vim.Diagnostic[]
        local filtered_diagnostics = {}
        for _, diagnostic in ipairs(diagnostics) do
          local should_filter = true
          local message = diagnostic.message
          -- Some mypy diagnostics range the entire function, so limit it to the first line.
          -- TODO: Limit this to the correct part of function signature.
          local function_messages = {
            'Function is missing a type annotation for one or more arguments',
            'Function is missing a return type annotation',
            'Function is missing a type annotation',
            'Use "-> None" if function does not return a value',
            'Missing return statement',
          }
          local matching_messages = vim.tbl_filter(function(function_message) ---@param function_message string
            return string.find(message, function_message) ~= nil or function_message == message
          end, function_messages)
          if #matching_messages > 0 then
            diagnostic.end_lnum = diagnostic.lnum
            diagnostic.end_col = 1000
          end
          -- Extend "x" is not defined diagnostic to the entire word instead of just the first character
          local undefined_variable_name = message:match('^Name "(.+)" is not defined $')
          if undefined_variable_name ~= nil then
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1]
            local start_col = buf_line:find(undefined_variable_name, diagnostic.col + 1)
            diagnostic.col = start_col and start_col - 1 or diagnostic.col
            diagnostic.end_lnum = diagnostic.lnum
            diagnostic.end_col = diagnostic.col + #undefined_variable_name
          end
          local undefined_module_attribute = message:match('^Module ".*" has no attribute "(.+)" $')
          if undefined_module_attribute ~= nil then
            local buf_line = vim.api.nvim_buf_get_lines(bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1]
            local start_col = buf_line:find(undefined_module_attribute, diagnostic.col + 1)
            diagnostic.col = start_col and start_col - 1 or diagnostic.col
            diagnostic.end_lnum = diagnostic.lnum
            diagnostic.end_col = diagnostic.col + #undefined_module_attribute
          end
          if should_filter then
            filtered_diagnostics[#filtered_diagnostics + 1] = diagnostic
          end
        end
        return filtered_diagnostics
      end
      local mypy_config_path = cwd .. '/mypy.ini'
      local dmypy_args = {
        'run',
        '--timeout',
        '50000',
        '--',
        '--show-column-numbers',
        '--show-error-end',
        '--hide-error-context',
        '--no-color-output',
        '--no-error-summary',
        '--no-pretty',
        '--config-file',
        mypy_config_path,
      }
      require('lint').linters.dmypy.args = dmypy_args
      require('lint').linters.pylint.env = {
        PYTHONPATH = cwd .. ':' .. cwd .. '/' .. Python.GEN_FILES_PATH,
      }
      local original_pylint_parser = require('lint').linters.pylint.parser
      require('lint').linters.pylint.parser = function(output, bufnr, linter_cwd)
        local diagnostics = original_pylint_parser(output, bufnr, linter_cwd)
        ---@type vim.Diagnostic[]
        local filtered_diagnostics = {}
        for _, diagnostic in ipairs(diagnostics) do
          local should_filter = true
          if diagnostic.code == 'E0611' and diagnostic.message:find('_pb2') then
            should_filter = false
          end
          if should_filter then
            filtered_diagnostics[#filtered_diagnostics + 1] = diagnostic
          end
        end
        return filtered_diagnostics
      end
      require('lint').linters.pylint.args = {
        '-f',
        'json',
        '--from-stdin',
        '--disable=' .. table.concat(Python.DISABLED_PYLINT_RULES, ','),
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      }
      require('lint').linters.buildifier.args = {
        '-lint',
        'warn',
        '-mode',
        'check',
        get_buildifier_warnings_arg(),
        '-format',
        'json',
        '-type',
        get_buildifier_filetype,
      }
      require('lint').linters_by_ft = {
        bzl = { 'buildifier' },
        go = { 'golint' },
        proto = { 'buf_lint' },
        python = { 'dmypy', 'pylint' },
        json = { 'jq' },
        fish = { 'fish' },
      }
    end,
  },
}
