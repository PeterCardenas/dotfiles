local async = require('utils.async')

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufEnter' }, {
  desc = 'Lint on write',
  group = vim.api.nvim_create_augroup('LintOnWrite', { clear = true }),
  callback = function()
    require('lint').try_lint()
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

  success, output = shell.async_cmd('fish', { '-c', string.format('bazel %s build --color=no %s', output_base_flag, table.concat(matched_targets, ' ')) })
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

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  desc = 'Setup formatting',
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    require('plugins.lsp.format').setup_formatting_diagnostic(bufnr)
    vim.keymap.set({ 'n', 'v' }, '<leader>lf', function()
      require('plugins.lsp.format').format(bufnr)
    end, {
      desc = 'LSP: Format buffer',
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
      require('conform').setup({
        formatters_by_ft = {
          lua = { 'stylua' },
          go = { 'golines' },
          bzl = { 'buildifier' },
          json = { 'jq' },
          jsonc = { 'jq' },
          fish = { 'fish_indent' },
          sh = { 'shfmt' },
        },
        formatters = {
          buildifier = {
            ---@type fun(self: conform.JobFormatterConfig, ctx: conform.Context): string|string[]
            args = function(_, ctx)
              local filetype = get_buildifier_filetype(ctx.buf)
              return { '-lint=fix', '-warnings=all', '-type', filetype }
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
      require('lint').linters.golint = {
        name = 'golint',
        cmd = 'golint',
        stdin = false,
        ignore_exitcode = true,
        parser = require('lint.parser').from_pattern('([^:]+):([0-9]+):([0-9]+): (.+)', { 'filename', 'lnum', 'col', 'message' }),
      }
      require('lint').linters_by_ft = {
        bzl = { 'buildifier' },
        go = { 'golint' },
      }
    end,
  },
}
