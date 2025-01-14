---@param client vim.lsp.Client
---@param bufnr integer
local function on_attach(client, bufnr)
  if client.name == require('typescript-tools.config').plugin_name then
    -- Defer to eslint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
    client.server_capabilities.semanticTokensProvider = nil
  end
  require('plugins.lsp.on_attach').on_attach(client, bufnr)
  vim.keymap.set({ 'n' }, 'gD', function()
    require('typescript-tools.api').go_to_source_definition(false)
  end, { buffer = bufnr })
end

---@type LazyPluginSpec
return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  ft = require('utils.typescript').SUPPORTED_FT,
  config = function()
    -- Following issues remain:
    --  - Cannot view document symbols while project is loading.
    require('typescript-tools').setup({
      on_attach = on_attach,
      settings = {
        tsserver_max_memory = 8192,
        separate_diagnostic_server = true,
        complete_function_calls = false,
        publish_diagnostic_on = 'insert_leave',
        tsserver_format_options = {
          indentSize = 2,
          convertTabsToSpaces = true,
        },
        tsserver_file_preferences = {
          includeInlayEnumMemberValueHints = true,
          includeInlayParameterNameHints = 'literals',
          importModuleSpecifierPreference = 'non-relative',
          quotePreference = 'single',
        },
        tsserver_logs = 'verbose',
        jsx_close_tag = {
          enable = true,
        },
      },
    })
  end,
}
