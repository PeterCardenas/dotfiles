local M = {}

---Setup language servers found locally.
---@param capabilities lsp.ClientCapabilities
function M.setup(capabilities)
  -- Setup language servers found locally.
  -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  ---@type table<string, lspconfig.Config>
  local custom_servers = {
    pls = {
      enabled = false,
      cmd = { 'protobuf-ls', 'server', '--mode', 'stdio' },
      filetypes = { 'proto' },
      default_config = {
        root_dir = require('lspconfig.util').root_pattern('.git'),
      },
    },
    fishls = {
      enabled = false,
      cmd = { 'fish-ls', '--stdio' },
      filetypes = { 'fish' },
      default_config = {
        root_dir = require('lspconfig.util').root_pattern('.git'),
      },
    },
    valels = {
      cmd = { 'vale-ls' },
      filetypes = { 'markdown', 'text', 'dosini', 'yaml' },
      default_config = {
        root_dir = require('lspconfig.util').root_pattern('.vale.ini'),
      },
    },
  }

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
end

return M
