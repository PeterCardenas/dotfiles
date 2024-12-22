local async = require('utils.async')

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

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter', 'BufNewFile' }, {
  desc = 'Lint on write',
  group = vim.api.nvim_create_augroup('LintOnWrite', { clear = true }),
  callback = function()
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
    exec()
  end
end

---@async
---@param abs_filepath string
local function bazel_go_lint(abs_filepath)
  local workspace_root = require('utils.file').get_ancestor_dir('WORKSPACE')
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
  success, output = shell.async_cmd('fish', { '-c', string.format('bazel %s query --color=no "%s"', output_base_flag, query_targets) })
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
      table.insert(matched_targets, target)
    end
  end

  success, output = shell.async_cmd(
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
    table.insert(file_diagnostics[filename], diagnostic)
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
      async.void(
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
      async.void(
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

---@type table<number, boolean>
local bufs_setup = {}
vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  desc = 'Setup formatting',
  callback = function(args)
    local bufnr = args.buf
    if bufs_setup[bufnr] then
      return
    end
    bufs_setup[bufnr] = true
    require('plugins.lsp.format').setup_formatting_diagnostic(bufnr)
    vim.keymap.set({ 'n', 'v' }, '<leader>lf', function()
      require('plugins.lsp.format').format(bufnr)
    end, {
      desc = 'Format buffer',
      buffer = bufnr,
    })
  end,
})

---@type LazyPluginSpec[]
return {
  -- Formatting.
  {
    'stevearc/conform.nvim',
    lazy = true,
    config = function()
      local file_utils = require('utils.file')
      require('conform').setup({
        formatters_by_ft = {
          lua = { 'stylua' },
          go = { 'golines' },
          bzl = { 'buildifier' },
          json = { 'jq' },
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
              return { '-lint=fix', '--warnings=all', '-warnings=-native-cc', '-type', filetype }
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
    -- TODO: Revert back to main repo once https://github.com/mfussenegger/nvim-lint/pull/688 is merged.
    'PeterCardenas/nvim-lint',
    branch = 'fix-parallel-try-lint-lag',
    lazy = true,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('lint').linters.golint = {
        name = 'golint',
        cmd = 'golint',
        stdin = false,
        ignore_exitcode = true,
        parser = require('lint.parser').from_pattern('([^:]+):([0-9]+):([0-9]+): (.+)', { 'filename', 'lnum', 'col', 'message' }),
      }
      local buf_lint_args = { 'lint', '--error-format', 'json' }
      local file_utils = require('utils.file')
      local cwd = file_utils.get_cwd()
      local buf_config_path = cwd .. '/buf.yaml'
      table.insert(buf_lint_args, '--config')
      table.insert(buf_lint_args, buf_config_path)
      table.insert(buf_lint_args, '--path')
      require('lint').linters.buf_lint.args = buf_lint_args
      require('lint').linters.buf_lint.cwd = cwd
      local venv_path = require('plugins.lsp.python').VENV_PATH
      local mypypath = table.concat({ cwd, cwd .. '/' .. require('plugins.lsp.python').GEN_FILES_PATH }, ':')
      require('lint').linters.dmypy.env = {
        VIRTUAL_ENV = venv_path,
        COLUMNS = 1000,
        MYPYPATH = mypypath,
      }
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
      require('lint').linters.dmypy.cmd = venv_path .. '/bin/dmypy'
      require('lint').linters.pylint.cmd = venv_path .. '/bin/pylint'
      require('lint').linters.pylint.env = {
        VIRTUAL_ENV = venv_path,
        PYTHONPATH = cwd .. ':' .. cwd .. '/' .. require('plugins.lsp.python').GEN_FILES_PATH,
      }
      require('lint').linters.pylint.args = {
        '-f',
        'json',
        '--from-stdin',
        '--disable=' .. table.concat(require('plugins.lsp.python').DISABLED_PYLINT_RULES, ','),
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      }
      require('lint').linters_by_ft = {
        bzl = { 'buildifier' },
        go = { 'golint' },
        proto = { 'buf_lint' },
        python = { 'dmypy', 'pylint' },
      }
    end,
  },
}
