vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  desc = 'Lint on write',
  group = vim.api.nvim_create_augroup('LintOnWrite', { clear = true }),
  callback = function()
    require('lint').try_lint()
  end,
})

local nogo_diagnostic_ns = vim.api.nvim_create_namespace('GoBazelLint')

---Map of filenames to functions that will lint the file.
---@type table<string, fun(): nil>
local bazel_go_lint_queue = {}

local function enqueue_next_bazel_go_lint()
  local filename, exec = next(bazel_go_lint_queue)
  if filename then
    bazel_go_lint_queue[filename] = nil
    exec()
  end
end

---@param abs_filepath string
local function bazel_go_lint(abs_filepath)
  ---@type fun(path: string): string|nil
  local get_workspace_root = require('lspconfig.util').root_pattern('WORKSPACE')
  local workspace_root = get_workspace_root(abs_filepath)
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
  local stdout = vim.loop.new_pipe()
  ---@type string[]
  local matched_targets = {}
  local handle = vim.loop.spawn('fish', {
    args = { '-c', string.format('bazel %s query "%s"', output_base_flag, query_targets) },
    cwd = workspace_root,
    stdio = { nil, stdout, nil },
  })
  if not handle then
    vim.notify('Failed to spawn bazel query', vim.log.levels.ERROR)
    enqueue_next_bazel_go_lint()
    return
  end
  vim.loop.read_start(stdout, function(query_err, query_data)
    assert(not query_err, query_err)
    if query_data then
      if string.match(query_data, '^//') then
        table.insert(matched_targets, query_data)
      end
    else
      stdout:close()
      local stderr = vim.loop.new_pipe()
      handle = vim.loop.spawn('fish', {
        args = { '-c', string.format('bazel %s build %s', output_base_flag, table.concat(matched_targets, ' ')) },
        cwd = workspace_root,
        stdio = { nil, nil, stderr },
      })
      if not handle then
        enqueue_next_bazel_go_lint()
        vim.notify('Failed to spawn bazel build', vim.log.levels.ERROR)
        return
      end

      ---@type table<string, lsp.Diagnostic[]>
      local file_diagnostics = {}
      vim.loop.read_start(stderr, function(err, data)
        assert(not err, err)
        if data then
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
            ---@type lsp.Diagnostic
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
          local lines = vim.split(data, '\n')
          for _, line in ipairs(lines) do
            parse_line(line)
          end
        else
          stderr:close()
          local function set_diagnostics()
            vim.diagnostic.reset(nogo_diagnostic_ns)
            for filename, diagnostics in pairs(file_diagnostics) do
              local file_uri = vim.uri_from_fname(workspace_root .. '/' .. filename)
              local bufnr = vim.uri_to_bufnr(file_uri)
              if not vim.api.nvim_buf_is_loaded(bufnr) then
                vim.fn.bufload(bufnr)
              end
              vim.bo[bufnr].buflisted = true
              vim.diagnostic.set(nogo_diagnostic_ns, bufnr, diagnostics, { underline = true })
              enqueue_next_bazel_go_lint()
            end
          end
          vim.schedule(set_diagnostics)
        end
      end)
      handle:close()
    end
  end)
  vim.loop.close(handle)
end

vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  desc = 'Lint from bazel build output on write',
  group = vim.api.nvim_create_augroup('GoBazelLint', { clear = true }),
  pattern = '*.go',
  callback = function()
    local abs_filepath = vim.fn.expand('%:p')
    if type(abs_filepath) ~= 'string' then
      return
    end
    if #bazel_go_lint_queue == 0 then
      bazel_go_lint(abs_filepath)
    end
    bazel_go_lint_queue[abs_filepath] = function()
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
          go = { 'gofumpt', 'golines' },
          bzl = { 'buildifier' },
          json = { 'jq' },
          jsonc = { 'jq' },
          fish = { 'fish_indent' },
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
          fish_indent = {
            args = { '--write' },
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
