vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  callback = function()
    require('lint').try_lint()
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
          go = { 'gofumpt', 'golines' },
          bzl = { 'buildifier' },
          json = { 'jq' },
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
