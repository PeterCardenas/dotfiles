vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  callback = function()
    require('lint').try_lint()
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
        },
        formatters = {
          buildifier = {
            ---@type fun(self: conform.JobFormatterConfig, ctx: conform.Context): string|string[]
            args = function(_, ctx)
              local filetype = get_buildifier_filetype(ctx.buf)
              return { '-lint=fix', '-warnings=all', '-type', filetype }
            end,
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
      require('lint').linters_by_ft = {
        bzl = { 'buildifier' },
      }
    end,
  },
}
