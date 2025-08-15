local TypeScript = require('utils.typescript')
local OnAttach = require('plugins.lsp.on_attach')

---@param client vim.lsp.Client
---@param bufnr integer
local function on_attach(client, bufnr)
  if client.name == require('typescript-tools.config').plugin_name then
    -- Defer to eslint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
    client.server_capabilities.semanticTokensProvider = nil
  end
  OnAttach.on_attach(client, bufnr)
  vim.keymap.set({ 'n' }, 'gS', function()
    require('typescript-tools.api').go_to_source_definition(false)
  end, { buffer = bufnr, desc = 'Go to source definition' })
end

-- TODO: Add LspDetach support
---@type LazyPluginSpec
return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  ft = TypeScript.SUPPORTED_FT,
  config = function()
    -- Following issues remain:
    --  - Cannot view document symbols while project is loading.
    ---@type vim.lsp.Config
    local config = {
      on_attach = on_attach,
      ---@param filename string
      ---@param bufnr integer
      ---@return string?
      root_dir = function(filename, bufnr)
        if vim.startswith(filename, 'octo:/') then
          return
        end
        local root_dir = vim.fs.root(bufnr, { 'tsconfig.json', 'package.json', '.git' })
        if not root_dir then
          return
        end
        -- INFO: this is needed to make sure we don't pick up root_dir inside node_modules
        local node_modules_index = root_dir and root_dir:find('node_modules', 1, true)
        if node_modules_index and node_modules_index > 0 then
          root_dir = root_dir:sub(1, node_modules_index - 2)
        end

        return root_dir
      end,
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
    }

    require('typescript-tools').setup(config)
  end,
}
