---@type LazyPluginSpec
return {
  'pmizio/typescript-tools.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  config = function()
    -- Still uncertain if we should enable this by default.
    -- Following issues remain:
    --  - Cannot view document symbols while project is loading.
    if require('utils.config').tsserver_enabled then
      return
    end
    require('typescript-tools').setup({
      on_attach = require('plugins.lsp.on_attach').on_attach,
      settings = {
        tsserver_max_memory = 8192,
        separate_diagnostic_server = false,
        complete_function_calls = true,
        tsserver_file_preferences = {
          includeInlayEnumMemberValueHints = true,
          includeInlayParameterNameHints = 'literals',
          importModuleSpecifierPreference = 'non-relative',
        },
        jsx_close_tag = {
          enable = true,
        },
      },
    })
  end,
}
