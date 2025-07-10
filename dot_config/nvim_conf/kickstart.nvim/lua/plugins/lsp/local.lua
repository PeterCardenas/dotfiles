local Config = require('utils.config')
local Table = require('utils.table')
local M = {}

---@class LspTogglableConfig : vim.lsp.Config
---@field enabled? boolean

---Setup language servers found locally.
---@param capabilities lsp.ClientCapabilities
function M.setup(capabilities)
  -- Setup language servers found locally.
  -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  ---@type table<string, LspTogglableConfig>
  local custom_servers = {
    emmylua_ls = {
      enabled = vim.fn.executable('emmylua_ls') == 1 and Config.USE_RUST_LUA_LS,
      cmd = { 'emmylua_ls' },
      filetypes = { 'lua' },
      root_markers = { 'lua/' },
      cmd_env = {
        RUST_BACKTRACE = 'full',
      },
      settings = {
        Lua = {
          diagnostics = {
            disable = { 'unnecessary-if' },
          },
          workspace = {
            ignoreGlobs = { '**/nvim-highlight-colors/**/*_spec.lua' },
            enableReindex = true,
          },
          strict = {
            requirePath = true,
            typeCall = true,
            arrayIndex = false,
          },
        },
      },
    },
  }

  for server_name, server_config in pairs(custom_servers) do
    if server_config.enabled ~= false then
      vim.lsp.config[server_name] = server_config
      vim.lsp.enable(server_name)
    end
  end

  local home = os.getenv('HOME')
  ---@type vim.lsp.Config
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
      fish_lsp_log_file = '/tmp/fish-lsp.log',
      fish_lsp_enable_experimental_diagnostics = true,
    },
  }
  local current_fish_config = vim.lsp.config['fish_lsp'] or {}
  local merged_fish_config = Table.merge_tables(current_fish_config, fish_lsp_config)
  vim.lsp.config('fish_lsp', merged_fish_config)
  vim.lsp.enable('fish_lsp')

  ---@type vim.lsp.Config
  local bazelrc_lsp_config = {
    capabilities = capabilities,
    cmd_env = {
      RUST_BACKTRACE = 'full',
      BAZELRC_LSP_RUN_BAZEL_PATH = 'bazelisk',
    },
  }
  local current_bazelrc_config = vim.lsp.config['bazelrc_lsp'] or {}
  local merged_bazelrc_config = Table.merge_tables(current_bazelrc_config, bazelrc_lsp_config)
  vim.lsp.config('bazelrc_lsp', merged_bazelrc_config)
  vim.lsp.enable('bazelrc_lsp')

  local ccls_capabilities = Table.merge_tables(capabilities, {
    offsetEncoding = { 'utf-16' },
    general = {
      positionEncodings = { 'utf-16' },
    },
  })
  if not Config.USE_CLANGD then
    ---@type vim.lsp.Config
    local ccls_config = {
      capabilities = ccls_capabilities,
      offset_encoding = 'utf-16',
    }
    local current_ccls_config = vim.lsp.config['ccls'] or {}
    local merged_ccls_config = Table.merge_tables(current_ccls_config, ccls_config)
    vim.lsp.config('ccls', merged_ccls_config)
    vim.lsp.enable('ccls')
  end

  ---@type vim.lsp.Config
  local sourcekit_config = {
    capabilities = capabilities,
    filetypes = { 'swift', 'objc', 'objcpp' },
  }
  local current_sourcekit_config = vim.lsp.config['sourcekit'] or {}
  local merged_sourcekit_config = Table.merge_tables(current_sourcekit_config, sourcekit_config)
  vim.lsp.config('sourcekit', merged_sourcekit_config)
  vim.lsp.enable('sourcekit')

  ---@type vim.lsp.Config
  local protols_config = {
    capabilities = capabilities,
  }
  local current_protols_config = vim.lsp.config['protols'] or {}
  local merged_protols_config = Table.merge_tables(current_protols_config, protols_config)
  vim.lsp.config('protols', merged_protols_config)
  vim.lsp.enable('protols')

  ---@type vim.lsp.Config
  local gh_actions_ls_config = {
    capabilities = capabilities,
    filetypes = { 'yaml.github' },
  }
  local current_gh_actions_ls_config = vim.lsp.config['gh_actions_ls'] or {}
  local merged_gh_actions_ls_config = Table.merge_tables(current_gh_actions_ls_config, gh_actions_ls_config)
  vim.lsp.config('gh_actions_ls', merged_gh_actions_ls_config)
  vim.lsp.enable('gh_actions_ls')

  ---@type vim.lsp.Config
  local ts_query_ls_config = {
    capabilities = capabilities,
    init_options = {
      parser_install_directories = {
        vim.fs.joinpath(vim.fn.stdpath('data'), '/lazy/nvim-treesitter/parser/'),
      },
      parser_aliases = {
        ecma = 'javascript',
      },
    },
  }
  local current_ts_query_ls_config = vim.lsp.config['ts_query_ls'] or {}
  local merged_ts_query_ls_config = Table.merge_tables(current_ts_query_ls_config, ts_query_ls_config)
  vim.lsp.config('ts_query_ls', merged_ts_query_ls_config)
  vim.lsp.enable('ts_query_ls')

  ---@type vim.lsp.Config
  local starpls_config = {
    capabilities = capabilities,
    cmd = { 'starpls', 'server', '--experimental_infer_ctx_attributes', '--experimental_use_code_flow_analysis' },
    cmd_env = {
      RUST_BACKTRACE = 'full',
    },
  }
  local current_starpls_config = vim.lsp.config['starpls'] or {}
  local merged_starpls_config = Table.merge_tables(current_starpls_config, starpls_config)
  vim.lsp.config('starpls', merged_starpls_config)
  vim.lsp.enable('starpls')
end

return M
