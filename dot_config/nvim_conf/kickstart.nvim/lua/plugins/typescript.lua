---@param client vim.lsp.Client
---@param bufnr integer
local function on_attach(client, bufnr)
  if client.name == require('typescript-tools.config').plugin_name then
    -- Defer to eslint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  require('plugins.lsp.on_attach').on_attach(client, bufnr)
end

---@type LazyPluginSpec
return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  config = function()
    -- Still uncertain if we should enable this by default.
    -- Following issues remain:
    --  - Cannot view document symbols while project is loading.
    require('typescript-tools').setup({
      on_attach = on_attach,
      settings = {
        tsserver_max_memory = 8192,
        separate_diagnostic_server = false,
        complete_function_calls = true,
        tsserver_file_preferences = {
          includeInlayEnumMemberValueHints = true,
          includeInlayParameterNameHints = 'literals',
          importModuleSpecifierPreference = 'non-relative',
          quotePreference = 'single',
        },
        jsx_close_tag = {
          enable = true,
        },
      },
    })
  end,
}
