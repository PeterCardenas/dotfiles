local Config = require('utils.config')
local M = {}

-- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
---@class LspTogglableConfig : vim.lsp.Config
---@field enabled? boolean

---Setup language servers found locally.
---@param current_config table<string, LspTogglableConfig>
function M.add_config(current_config)
  current_config['emmylua_ls'] = {
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
          disable = { 'unnecessary-if', 'redundant-return-value' },
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
  }

  local home = os.getenv('HOME')
  current_config['fish_lsp'] = {
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

  current_config['bazelrc_lsp'] = {
    cmd_env = {
      RUST_BACKTRACE = 'full',
      BAZELRC_LSP_RUN_BAZEL_PATH = 'bazelisk',
    },
  }

  if not Config.USE_CLANGD then
    current_config['ccls'] = {
      capabilities = {
        offsetEncoding = { 'utf-16' },
        general = {
          positionEncodings = { 'utf-16' },
        },
      },
      offset_encoding = 'utf-16',
    }
  end

  current_config['sourcekit'] = {
    enabled = vim.fn.has('mac') == 1,
    filetypes = { 'swift', 'objc', 'objcpp' },
  }

  current_config['protols'] = {}

  current_config['gh_actions_ls'] = {
    filetypes = { 'yaml.github' },
  }

  current_config['ts_query_ls'] = {
    init_options = {
      parser_install_directories = {
        vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], '/lazy/nvim-treesitter/parser/'),
      },
      parser_aliases = {
        ecma = 'javascript',
      },
    },
  }

  current_config['starpls'] = {
    cmd = {
      'starpls',
      'server',
      '--experimental_infer_ctx_attributes',
      '--experimental_use_code_flow_analysis',
      '--experimental_goto_definition_skip_re_exports',
    },
    cmd_env = {
      RUST_BACKTRACE = 'full',
    },
  }
end

return M
