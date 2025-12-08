local Config = require('utils.config')
local File = require('utils.file')

--- Discover all plugins that are defined in lazy.nvim spec and aggregate their paths.
--- Does not handle packspec/rockspec.
---@return string[]
function get_plugin_paths()
  local static = {
    -- other static paths you might want to include
    vim.env.HOME .. '/.local/share/chezmoi/dot_config/nvim_conf/kickstart.nvim/lua',
    vim.env.VIMRUNTIME .. '/lua',
  }
  ---@diagnostic disable-next-line: unnecessary-if
  if not vim.g.lazy_did_setup then
    return static
  end
  local spec = require('lazy.core.config').spec
  local paths = {}
  local plugins = vim.list_extend(vim.tbl_keys(spec.plugins), vim.tbl_keys(spec.disabled))
  for _, plugin_name in ipairs(plugins) do
    local plugin = spec.plugins[plugin_name] or spec.disabled[plugin_name]
    local luapath = vim.fs.joinpath(plugin.dir, 'lua')
    if vim.uv.fs_stat(luapath) then
      paths[#paths + 1] = luapath
    else
      paths[#paths + 1] = plugin.dir
    end
  end
  if vim.fn.isdirectory(File.get_cwd() .. '/lua') == 1 then
    paths[#paths + 1] = File.get_cwd() .. '/lua'
  end
  -- VIMRUNTIME needs to be last, otherwise some random module setting _G.vim = _G.vim or {...} (seen in test files)
  -- overrides the official implementation. This is true for emmylua_ls 0.13.0 at least.
  return vim.list_extend(paths, static)
end

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
    on_attach = function(client, _bufnr)
      -- Defer to stylua for formatting.
      client.server_capabilities.documentFormattingProvider = false
      client.server_capabilities.documentRangeFormattingProvider = false
    end,
    capabilities = {
      workspace = {
        diagnostics = {
          refreshSupport = false,
        },
      },
    },
    settings = {
      Lua = {
        diagnostics = {
          disable = { 'unnecessary-if', 'redundant-return-value' },
        },
        workspace = {
          -- HACK: lazydev doesn't play well with emmylua_ls, so we need to manually add all the plugin paths.
          library = get_plugin_paths(),
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
    on_attach = function(client, _bufnr)
      -- Defer to fish_indent for formatting.
      client.server_capabilities.documentFormattingProvider = false
      client.server_capabilities.documentRangeFormattingProvider = false
    end,
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
      on_attach = function(client, _bufnr)
        -- Defer to clang-format for formatting.
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
      end,
    }
  end

  current_config['sourcekit'] = {
    enabled = vim.fn.has('mac') == 1,
    filetypes = { 'swift', 'objc', 'objcpp' },
  }

  current_config['protols'] = {
    on_attach = function(client, _bufnr)
      -- Defer to clang-format for formatting.
      client.server_capabilities.documentFormattingProvider = false
      client.server_capabilities.documentRangeFormattingProvider = false
    end,
  }

  current_config['gh_actions_ls'] = {
    filetypes = { 'yaml.github' },
  }

  local nvim_treesitter_config_path = vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], '/lazy/nvim-treesitter/.tsqueryrc.json')
  local nvim_treesitter_config_str = File.read_file(nvim_treesitter_config_path)
  local success, config = pcall(vim.json.decode, nvim_treesitter_config_str)
  if not success then
    vim.notify('Failed to parse nvim-treesitter config: ' .. nvim_treesitter_config_str, vim.log.levels.ERROR)
    config = {}
  else
    config.valid_directives.maybe_conceal_whole_line = {
      description = 'Conceal the whole line if the match covers entire lines.',
      parameters = { { type = 'capture', arity = 'required' } },
    }
    config.valid_captures.images = {
      ['image'] = 'what the image should replace/represent',
      ['image.src'] = 'url/path to the image',
    }
  end
  current_config['ts_query_ls'] = {
    init_options = config,
    on_attach = function(_client, bufnr)
      -- TODO: use completion fromo ts_query_ls
      vim.bo[bufnr].omnifunc = 'v:lua.vim.treesitter.query.omnifunc'
    end,
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
    on_attach = function(client, bufnr)
      vim.api.nvim_buf_create_user_command(bufnr, 'StarlarkSyntaxTree', function()
        local method = 'starpls/showSyntaxTree'

        local params = {
          textDocument = {
            uri = vim.uri_from_bufnr(bufnr),
          },
        }

        client:request(method, params, function(err, result, _)
          if err then
            vim.print('Error: ' .. err.message)
            return
          end

          vim.print('Starlark syntax tree:', vim.inspect(result):gsub('\\n', '\n'))
        end)
      end, { nargs = 0 })
    end,
  }
end

return M
