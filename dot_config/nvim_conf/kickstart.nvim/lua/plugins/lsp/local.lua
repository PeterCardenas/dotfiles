local Config = require('utils.config')
local Table = require('utils.table')
local M = {}

---Setup language servers found locally.
---@param capabilities lsp.ClientCapabilities
function M.setup(capabilities)
  -- Setup language servers found locally.
  -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  ---@type table<string, lspconfig.Config>
  local custom_servers = {
    emmylua_ls = {
      enabled = vim.fn.executable('emmylua_ls') == 1 and Config.USE_RUST_LUA_LS,
      cmd = { 'emmylua_ls' },
      filetypes = { 'lua' },
      default_config = {
        root_dir = require('lspconfig.util').root_pattern('lua'),
      },
      cmd_env = {
        RUST_BACKTRACE = 'full',
      },
    },
  }

  ---@param server_name string
  local function setup_server(server_name)
    local server_config = custom_servers[server_name]
    if server_config.enabled == false then
      return
    end
    ---@class DefaultLSPConfig
    ---@field default_config lspconfig.Config

    ---@type DefaultLSPConfig
    require('lspconfig.configs')[server_name] = {
      default_config = {
        cmd = server_config.cmd,
        cmd_env = server_config.cmd_env,
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

  local home = os.getenv('HOME')
  ---@type custom.LspConfig
  local fish_lsp_config = {
    capabilities = capabilities,
    init_options = {
      fish_lsp_all_indexed_paths = {
        home .. '/.local/share/chezmoi/dot_config/fish',
        '/usr/share/fish',
      },
      fish_lsp_modifiable_paths = {
        home .. '/.local/share/chezmoi/dot_config/fish',
      },
      fish_lsp_diagnostic_disable_error_codes = {
        4004,
      },
      fish_lsp_logfile = '/tmp/fish-lsp.log',
    },
  }
  require('lspconfig').fish_lsp.setup(fish_lsp_config)

  ---@type custom.LspConfig
  local bazelrc_lsp_config = {
    capabilities = capabilities,
    cmd_env = {
      RUST_BACKTRACE = 'full',
      BAZELRC_LSP_RUN_BAZEL_PATH = 'bazelisk',
    },
  }
  require('lspconfig').bazelrc_lsp.setup(bazelrc_lsp_config)

  local ccls_capabilities = Table.merge_tables(capabilities, {
    offsetEncoding = { 'utf-16' },
    general = {
      positionEncodings = { 'utf-16' },
    },
  })
  if not Config.USE_CLANGD then
    ---@type custom.LspConfig
    local ccls_config = {
      capabilities = ccls_capabilities,
      offset_encoding = 'utf-16',
    }
    require('lspconfig').ccls.setup(ccls_config)
  end

  ---@type custom.LspConfig
  local sourcekit_config = {
    capabilities = capabilities,
    filetypes = { 'swift', 'objc', 'objcpp' },
  }
  require('lspconfig').sourcekit.setup(sourcekit_config)

  ---@type custom.LspConfig
  local protols_config = {
    capabilities = capabilities,
  }
  require('lspconfig').protols.setup(protols_config)

  ---@type custom.LspConfig
  local gh_actions_ls_config = {
    capabilities = capabilities,
    filetypes = { 'yaml.github' },
  }
  require('lspconfig').gh_actions_ls.setup(gh_actions_ls_config)

  ---@type custom.LspConfig
  local ts_query_ls_config = {
    capabilities = capabilities,
  }
  require('lspconfig').ts_query_ls.setup(ts_query_ls_config)
end

return M
