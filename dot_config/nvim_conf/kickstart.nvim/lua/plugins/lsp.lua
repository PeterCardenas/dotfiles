-- [[ Configure LSP ]]

-- local LspMethod = vim.lsp.protocol.Methods

--- @class custom.LspConfig : lspconfig.Config
--- @field cmd? string[]|fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient

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
    require('plugins.lsp.on_attach').on_attach(client, args.buf)
  end,
})

---@return custom.LspConfig
local function gopls_config()
  --- @type custom.LspConfig
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
      gopls = {
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
      },
    },
  }

  return config
end

---@type LazyPluginSpec
return {
  -- LSP Configuration & Plugins
  'neovim/nvim-lspconfig',
  dependencies = {
    'williamboman/mason-lspconfig.nvim',

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
  ft = require('utils.lsp').FT_WITH_LSP,
  config = function()
    ---@type fun(path: string): string?
    local get_clangd_root = require('lspconfig.util').root_pattern('compile_commands.json')
    local clangd_root = get_clangd_root(vim.fn.expand('%:p:h'))
    local home = os.getenv('HOME')
    local clangd_enabled = clangd_root ~= nil and home ~= nil
    local compile_commands_dir = clangd_root ~= nil and '--compile-commands-dir=' .. clangd_root .. '/' or ''
    local clangd_cmd = home ~= nil and home .. '/.local/share/nvim/mason/bin/clangd' or ''
    local pnpm_home = os.getenv('PNPM_HOME')
    local tsserver_lib = pnpm_home ~= nil and pnpm_home .. '/global/5/node_modules/typescript/lib' or ''
    -- Enable the following language servers
    -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    ---@type table<string, custom.LspConfig>
    local servers = {
      clangd = {
        enabled = clangd_enabled and require('utils.config').USE_CLANGD,
        offset_encoding = 'utf-16',
        filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
        capabilities = {
          offsetEncoding = { 'utf-16' },
          general = {
            positionEncodings = { 'utf-16' },
          },
        },
        cmd = {
          clangd_cmd,
          '--header-insertion=never',
          '--compile-commands-dir=' .. compile_commands_dir,
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
      },
      gopls = gopls_config(),
      rust_analyzer = { enabled = false },
      -- Prefer to use nogo, but there is not language server for it yet.
      golangci_lint_ls = {
        init_options = {
          command = { 'golangci-lint', 'run', '--out-format', 'json', '--disable-all', '--enable', 'errcheck,ineffassign,unused' },
        },
      },
      eslint = {
        cmd_env = {
          NODE_OPTIONS = '--max-old-space-size=8192',
        },
      },
      stylelint_lsp = {
        filetypes = { 'css', 'scss' },
        settings = {
          stylelintplus = {
            autoFixOnFormat = true,
          },
        },
      },
      lua_ls = {
        enabled = not require('utils.config').USE_RUST_LUA_LS,
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
              },
              neededFileStatus = {
                ['await-in-sync'] = 'Opened',
              },
              globals = {
                'require',
              },
              unusedLocalExclude = { '_*' },
            },
          },
        },
      },
      bzl = {
        filetypes = { 'bzl' },
      },
      mdx_analyzer = {
        init_options = {
          typescript = {
            tsdk = tsserver_lib,
          },
        },
      },
      jsonls = {
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
                url = 'https://github.com/wraith13/vscode-schemas/raw/master/en/latest/schemas/settings/user.json',
              },
              {
                fileMatch = { 'vscode-keybindings.json' },
                url = 'https://github.com/wraith13/vscode-schemas/raw/master/en/latest/schemas/keybindings.json',
              },
              {
                fileMatch = { '.vscode/launch.json' },
                url = 'https://github.com/wraith13/vscode-schemas/raw/master/en/latest/schemas/launch.json',
              },
              {
                fileMatch = { '.vscode/tasks.json' },
                url = 'https://github.com/wraith13/vscode-schemas/raw/master/en/latest/schemas/tasks.json',
              },
              {
                fileMatch = { '.vscode/extensions.json' },
                url = 'https://github.com/wraith13/vscode-schemas/raw/master/en/latest/schemas/extensions.json',
              },
              {
                fileMatch = { 'swc.json', 'swc.*.json', '.swcrc', '.*.swcrc' },
                url = 'https://json.schemastore.org/swcrc.json',
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
      },
      yamlls = {
        filetypes = { 'yaml' },
        settings = {
          yaml = {
            ['schemaStore.enable'] = true,
          },
        },
        handlers = {
          -- [LspMethod.textDocument_publishDiagnostics] = function() end,
        },
      },
      taplo = {},
      vale_ls = {
        filetypes = { 'markdown', 'text', 'dosini', 'yaml', 'markdown.mdx' },
        root_dir = function(filename)
          local root_path = require('utils.file').get_ancestor_dir('.vale.ini', filename)
          ---@diagnostic disable-next-line: redundant-return-value
          return root_path
        end,
        single_file_support = false,
      },
      zls = {},
      vimls = {},
      glsl_analyzer = {},
      starpls = {
        cmd = { 'starpls', 'server', '--experimental_infer_ctx_attributes', '--experimental_use_code_flow_analysis' },
        cmd_env = {
          RUST_BACKTRACE = 'full',
        },
      },
    }
    local python_lsp_config = require('plugins.lsp.python').python_lsp_config()
    servers = require('utils.table').merge_tables(servers, python_lsp_config)

    -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities) ---@type lsp.ClientCapabilities

    -- Setup language servers found locally.
    require('plugins.lsp.local').setup(capabilities)
    -- Setup specific autocmds.
    require('plugins.lsp.python').setup()

    -- Ensure the servers above are installed
    local mason_lspconfig = require('mason-lspconfig')

    mason_lspconfig.setup({
      ensure_installed = {},
      automatic_installation = true,
    })

    mason_lspconfig.setup_handlers({
      function(server_name)
        local server_config = servers[server_name] or {}
        if server_config.enabled == false then
          return
        end
        ---@diagnostic disable-next-line: inject-field
        server_config.capabilities = require('utils.table').merge_tables(capabilities, server_config.capabilities or {})
        if server_name == 'ruff_lsp' then
          require('lspconfig.configs')[server_name] = require('lspconfig.configs.' .. server_name)
          require('lspconfig.configs')[server_name].setup(server_config)
        else
          require('lspconfig')[server_name].setup(server_config)
        end
      end,
    })
  end,
}
