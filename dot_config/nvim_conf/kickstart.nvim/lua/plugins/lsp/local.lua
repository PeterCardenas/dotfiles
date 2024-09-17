local M = {}

---Setup language servers found locally.
---@param capabilities lsp.ClientCapabilities
function M.setup(capabilities)
  -- Setup language servers found locally.
  -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  ---@type table<string, lspconfig.Config>
  local custom_servers = {}

  ---@param server_name string
  local function setup_server(server_name)
    local server_config = custom_servers[server_name]
    if server_config.enabled == false then
      return
    end
    require('lspconfig.configs')[server_name] = {
      default_config = {
        cmd = server_config.cmd,
        filetypes = server_config.filetypes,
        -- Cannot have functions in settings since they are not serializable.
        settings = {},
        ---@diagnostic disable-next-line: undefined-field
        root_dir = server_config.default_config.root_dir,
      },
    }
    require('lspconfig')[server_name].setup({
      capabilities = capabilities,
    })
  end

  for server_name, _ in pairs(custom_servers) do
    setup_server(server_name)
  end

  ---@type lspconfig.Config
  local fish_lsp_config = {
    capabilities = capabilities,
  }
  require('lspconfig').fish_lsp.setup(fish_lsp_config)

  ---@type lspconfig.Config
  local bazelrc_lsp_config = {
    capabilities = capabilities,
    cmd_env = {
      RUST_BACKTRACE = 'full',
    },
  }
  require('lspconfig').bazelrc_lsp.setup(bazelrc_lsp_config)

  local ccls_capabilities = require('utils.table').merge_tables(capabilities, {
    offsetEncoding = { 'utf-16' },
    general = {
      positionEncodings = { 'utf-16' },
    },
  })
  if not require('utils.config').USE_CLANGD then
    ---@type lspconfig.Config
    local ccls_config = {
      capabilities = ccls_capabilities,
      offset_encoding = 'utf-16',
    }
    require('lspconfig').ccls.setup(ccls_config)
  end

  ---@type lspconfig.Config
  local starpls_config = {
    capabilities = capabilities,
    cmd = { 'starpls', 'server', '--experimental_infer_ctx_attributes', '--experimental_use_code_flow_analysis' },
    cmd_env = {
      RUST_BACKTRACE = 'full',
    },
  }
  require('lspconfig').starpls.setup(starpls_config)
end

return M
