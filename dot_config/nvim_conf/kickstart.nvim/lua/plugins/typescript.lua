local TypeScript = require('utils.typescript')
local File = require('utils.file')

---@param client vim.lsp.Client
---@param bufnr integer
local function on_attach(client, bufnr)
  if client.name == require('typescript-tools.config').plugin_name then
    -- Defer to eslint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
    client.server_capabilities.semanticTokensProvider = nil
  end
  vim.keymap.set({ 'n' }, 'gS', function()
    require('typescript-tools.api').go_to_source_definition(false)
  end, { buffer = bufnr, desc = 'Go to source definition' })
end

-- TODO: Add LspDetach support
---@type LazyPluginSpec
return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  ft = TypeScript.SUPPORTED_FT,
  config = function()
    -- Following issues remain:
    --  - Cannot view document symbols while project is loading.
    ---@type vim.lsp.Config
    local config = {
      on_attach = on_attach,
      root_dir = function(bufnr, on_dir)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        if not File.file_exists(filename) then
          return
        end

        local util = require('typescript-tools.utils')
        on_dir(util.get_root_dir(bufnr))
      end,
      filetypes = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
    }
    local ts_settings = {
      tsserver_max_memory = 16384,
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
    }

    require('typescript-tools').setup({
      config = config,
      settings = ts_settings,
    })
  end,
}
