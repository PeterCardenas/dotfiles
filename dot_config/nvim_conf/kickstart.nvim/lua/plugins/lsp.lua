local File = require('utils.file')
local OnAttach = require('plugins.lsp.on_attach')
local Config = require('utils.config')
local Lsp = require('utils.lsp')
local Python = require('plugins.lsp.python')
local LocalLsp = require('plugins.lsp.local')
local Table = require('utils.table')
-- [[ Configure LSP ]]

local LspMethod = vim.lsp.protocol.Methods

vim.lsp.set_log_level('error')

-- Removes default behavior of autoformatting on save for zig
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*.zig',
  callback = function()
    local ok, zig_autocmds = pcall(vim.api.nvim_get_autocmds, { group = 'vim-zig' })
    if not ok then
      return
    end
    if zig_autocmds[1] then
      vim.api.nvim_del_augroup_by_id(zig_autocmds[1].group)
    end
  end,
})

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client == nil then
      return
    end
    OnAttach.on_attach(client, args.buf)
  end,
})

---@return LspTogglableConfig
local function gopls_config()
  local gopls_settings = {
    codelenses = {
      generate = false,
      gc_details = false,
      test = false,
      tidy = false,
      upgrade_dependency = false,
      vendor = false,
      regenerate_cgo = false,
    },
    completeFunctionCalls = true,
    completeUnimported = true,
    staticcheck = true,
    semanticTokens = true,
    hints = {
      assignVariableTypes = true,
      compositeLiteralFields = true,
      compositeLiteralTypes = true,
      constantValues = true,
      functionTypeParameters = true,
      parameterNames = true,
      rangeVariableTypes = true,
    },
  }
  --- @type LspTogglableConfig
  local config = {
    -- Disabled for performance reasons.
    -- Reference: https://github.com/neovim/neovim/issues/23291
    -- Possibly updating neovim can help: https://github.com/neovim/neovim/issues/23291#issuecomment-1817816570
    capabilities = {
      workspace = {
        didChangeWatchedFiles = {
          dynamicRegistration = false,
        },
      },
    },
    settings = {
      gopls = gopls_settings,
    },
  }

  return config
end

---@type LazyPluginSpec
return {
  -- LSP Configuration & Plugins
  'neovim/nvim-lspconfig',
  dependencies = {
    -- Useful status updates for LSP
    -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
    {
      'j-hui/fidget.nvim',
      tag = 'v1.5.0',
      config = function()
        require('fidget').setup({
          notification = {
            window = {
              winblend = 0,
            },
          },
          integration = {
            ['nvim-tree'] = {
              enable = false,
            },
            ['xcodebuild-nvim'] = {
              enable = false,
            },
          },
        })
      end,
    },
  },
  ft = Lsp.FT_WITH_LSP,
  config = function()
    ---@type string
    vim.env.PATH = vim.env.PATH .. ':' .. vim.fn.stdpath('data') .. '/mason/bin'
    local project_root = File.get_git_root() or File.get_cwd()

    ---@type table<string, LspTogglableConfig>
    local servers = {}

    ---@type fun(path: string): string?
    local get_clangd_root = require('lspconfig.util').root_pattern('compile_commands.json')
    local clangd_root = get_clangd_root(vim.fn.expand('%:p:h'))
    local home = os.getenv('HOME')
    local clangd_enabled = clangd_root ~= nil and home ~= nil
    servers.clangd = {
      enabled = clangd_enabled and Config.USE_CLANGD,
      offset_encoding = 'utf-16',
      filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
      capabilities = {
        offsetEncoding = { 'utf-16' },
        general = {
          positionEncodings = { 'utf-16' },
        },
      },
      cmd = {
        'clangd',
        '--header-insertion=never',
        '--query-driver=**',
        '--background-index',
        '--clang-tidy',
        '--completion-style=detailed',
        '--function-arg-placeholders',
        '--fallback-style=llvm',
      },
      init_options = {
        usePlaceholders = true,
        completeUnimported = true,
        clangdFileStatus = true,
      },
    }

    servers.gopls = gopls_config()

    servers.rust_analyzer = { enabled = false }

    -- Prefer to use nogo, but there is not language server for it yet.
    servers.golangci_lint_ls = {
      enabled = false,
      init_options = {
        command = { 'golangci-lint', 'run', '--output.json.path', 'stdout', '--default', 'none', '--enable', 'errcheck,ineffassign,unused' },
      },
    }

    servers.eslint = {
      cmd_env = {
        NODE_OPTIONS = '--max-old-space-size=8192',
      },
    }

    servers.stylelint_lsp = {
      filetypes = { 'css', 'scss' },
      settings = {
        stylelintplus = {
          autoFixOnFormat = true,
        },
      },
    }

    local lua_ls_path = 'lua-language-server'
    local tip_lua_ls_path = vim.fn.expand('~/projects/lua-language-server/bin/lua-language-server')
    if File.file_exists(tip_lua_ls_path) and Config.USE_LUA_LS_TIP then
      lua_ls_path = tip_lua_ls_path
    end
    servers.lua_ls = {
      enabled = not Config.USE_RUST_LUA_LS,
      cmd = { lua_ls_path },
      settings = {
        Lua = {
          workspace = {
            checkThirdParty = false,
          },
          telemetry = { enable = false },
          hint = { enable = true, arrayIndex = 'Disable' },
          diagnostics = {
            severity = {
              ['await-in-sync'] = 'Error',
              ['no-unknown'] = 'Warning',
            },
            neededFileStatus = {
              ['await-in-sync'] = 'Opened',
              ['no-unknown'] = 'Any',
            },
            globals = {
              'require',
            },
            unusedLocalExclude = { '_*' },
          },
        },
      },
    }

    servers.bzl = {
      enabled = false,
      filetypes = { 'bzl' },
    }

    local pnpm_home = os.getenv('PNPM_HOME')
    local tsserver_lib = pnpm_home ~= nil and pnpm_home .. '/global/5/node_modules/typescript/lib' or ''
    servers.mdx_analyzer = {
      init_options = {
        typescript = {
          tsdk = tsserver_lib,
        },
      },
    }

    servers.jsonls = {
      filetypes = { 'json', 'jsonc' },
      settings = {
        json = {
          validate = { enable = true },
          schemas = {
            {
              fileMatch = { 'package.json' },
              url = 'https://json.schemastore.org/package.json',
            },
            {
              fileMatch = { 'tsconfig.json', 'tsconfig.*.json' },
              url = 'https://json.schemastore.org/tsconfig.json',
            },
            {
              fileMatch = { 'pyrightconfig.json' },
              url = 'https://raw.githubusercontent.com/microsoft/pyright/main/packages/vscode-pyright/schemas/pyrightconfig.schema.json',
            },
            {
              fileMatch = { '.vscode/settings.json', 'vscode-settings.json' },
              url = 'https://github.com/wraith13/vscode-schemas/raw/master/schemas/json/settings.json',
            },
            {
              fileMatch = { 'vscode-keybindings.json' },
              url = 'https://github.com/wraith13/vscode-schemas/raw/master/schemas/json/keybindings.json',
            },
            {
              fileMatch = { '.vscode/launch.json' },
              url = 'https://github.com/wraith13/vscode-schemas/raw/master/schemas/json/launch.json',
            },
            {
              fileMatch = { '.vscode/tasks.json' },
              url = 'https://github.com/wraith13/vscode-schemas/raw/master/schemas/json/tasks.json',
            },
            {
              fileMatch = { '.vscode/extensions.json' },
              url = 'https://github.com/wraith13/vscode-schemas/raw/master/schemas/json/extensions.json',
            },
            {
              fileMatch = { 'swc.json', 'swc.*.json', '.swcrc', '.*.swcrc' },
              url = 'https://swc.rs/schema.json',
            },
            {
              fileMatch = { '.luarc.json' },
              url = 'https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json',
            },
            {
              fileMatch = { '.emmyrc.json' },
              url = 'https://github.com/CppCXY/emmylua-analyzer-rust/raw/refs/heads/main/resources/schema.json',
            },
          },
        },
      },
    }

    servers.yamlls = {
      filetypes = { 'yaml' },
      settings = {
        yaml = {
          ['schemaStore.enable'] = true,
        },
      },
    }

    servers.taplo = {}

    servers.vale_ls = {
      filetypes = { 'markdown', 'text', 'dosini', 'yaml', 'markdown.mdx' },
      root_dir = function(bufnr, cb)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local root_path = File.get_ancestor_dir('.vale.ini', filename)
        cb(root_path)
      end,
      single_file_support = false,
    }

    servers.zls = {
      handlers = {
        ---@param error lsp.ResponseError
        ---@param result lsp.PublishDiagnosticsParams
        ---@param ctx lsp.HandlerContext
        [LspMethod.textDocument_publishDiagnostics] = function(error, result, ctx)
          -- TODO: Fix these duplicated diagnostics upstream in zls
          -- Create a map from diagnostic location to diagnostic messages
          local loc_to_msgs = {} ---@type table<string, string[]>

          -- Process diagnostics to create location-to-message mapping and deduplicate
          local deduplicated_diagnostics = {} ---@type lsp.Diagnostic[]
          for _, diagnostic in ipairs(result.diagnostics) do
            -- Create a unique key for the location
            local loc_key = string.format(
              '%s:%d:%d-%d:%d',
              result.uri,
              diagnostic.range.start.line,
              diagnostic.range.start.character,
              diagnostic.range['end'].line,
              diagnostic.range['end'].character
            )

            -- Initialize the message array if it doesn't exist
            if not loc_to_msgs[loc_key] then
              loc_to_msgs[loc_key] = {}
            end

            -- Check if this message already exists for this location
            local message_exists = false
            for _, existing_msg in ipairs(loc_to_msgs[loc_key]) do
              if existing_msg == diagnostic.message then
                message_exists = true
                break
              end
            end

            -- Add the message if it's not a duplicate
            if not message_exists then
              loc_to_msgs[loc_key][#loc_to_msgs[loc_key] + 1] = diagnostic.message
              deduplicated_diagnostics[#deduplicated_diagnostics + 1] = diagnostic
            end
          end

          -- Replace the diagnostics with the deduplicated list
          result.diagnostics = deduplicated_diagnostics
          return vim.lsp.diagnostic.on_publish_diagnostics(error, result, ctx)
        end,
      },
      settings = {
        zls = {
          enable_build_on_save = true,
          build_on_save_args = { '-Doptimize=ReleaseFast', '-j4' },
        },
      },
    }

    servers.vimls = {}

    servers.glsl_analyzer = {}

    servers.buf_ls = {
      enabled = false,
    }

    servers.bashls = {}

    servers.graphql = {
      filetypes = { 'graphql' },
    }

    servers.marksman = {}

    Python.add_config(servers)

    -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
    local capabilities ---@type lsp.ClientCapabilities
    if Config.USE_BLINK_CMP then
      capabilities = require('blink.cmp').get_lsp_capabilities() ---@type lsp.ClientCapabilities
    else
      capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities) ---@type lsp.ClientCapabilities
    end

    -- Setup language servers found locally.
    LocalLsp.add_config(servers)
    -- Setup specific autocmds and ruff_lsp.
    Python.setup()

    for server_name, server_config in pairs(servers) do
      if server_config.enabled ~= false then
        server_config.capabilities = Table.merge_tables(capabilities, server_config.capabilities or {})
        local existing_config = vim.lsp.config[server_name]
        local merged_config ---@type vim.lsp.Config
        if existing_config then
          merged_config = Table.merge_tables(existing_config, server_config)
        else
          merged_config = server_config
        end
        -- Prevent LSP from attaching to octo:// buffers
        local original_root_dir = merged_config.root_dir
        merged_config.root_dir = function(bufnr, on_dir)
          local filename = vim.api.nvim_buf_get_name(bufnr)
          if not File.file_exists(filename) then
            return
          end
          if original_root_dir then
            return original_root_dir(bufnr, on_dir)
          end
          for _, marker in ipairs(merged_config.root_markers or {}) do
            local root = vim.fs.root(bufnr, marker)
            if root then
              return on_dir(root)
            end
          end
          on_dir(nil)
        end
        vim.lsp.config[server_name] = merged_config
        vim.lsp.enable(server_name)
      end
    end
  end,
}
