-- [[ Configure LSP ]]

---@param bufnr integer
---@param ls_name string
---@param action_type string
---@param on_complete? function
local function commit_code_action_edit(bufnr, ls_name, action_type, on_complete)
  local params = vim.lsp.util.make_range_params()
  params.context = { only = { action_type }, diagnostics = {} }
  local clients = vim.lsp.get_clients({
    bufnr = bufnr,
    name = ls_name,
    method = "textDocument/codeAction",
  })
  local completion_count = 0
  for _, client in pairs(clients) do
    ---@diagnostic disable-next-line: invisible
    client.request(
      'textDocument/codeAction',
      params,
      function(err, ls_results, _, _)
        if err then
          vim.notify("Error running" .. ls_name .. " code action: " .. err, vim.log.levels.ERROR)
        end
        for _, ls_result in pairs(ls_results or {}) do
          if ls_result.edit then
            local offset_encoding = (vim.lsp.get_client_by_id(client.id) or {}).offset_encoding or "utf-16"
            vim.lsp.util.apply_workspace_edit(ls_result.edit, offset_encoding)
          end
        end
        completion_count = completion_count + 1
        if completion_count == #clients and on_complete then
          on_complete()
        end
      end,
      bufnr
    )
  end
end

---Organizes go imports.
---@param bufnr integer
local function format_go_imports(bufnr)
  commit_code_action_edit(bufnr, "gopls", "source.organizeImports")
end

---Fix all auto-fixable ruff lsp errors.
---@param bufnr integer
local function fix_ruff_errors(bufnr)
  commit_code_action_edit(bufnr, "ruff_lsp", "source.organizeImports", function()
    commit_code_action_edit(bufnr, "ruff_lsp", "source.fixAll")
  end)
end

--  This function gets run when an LSP connects to a particular buffer.
---@param client lsp.Client
---@param bufnr integer
local on_attach = function(client, bufnr)
  -- Defer to pylsp for hover documentation.
  if client.name == 'ruff_lsp' then
    client.server_capabilities.hoverProvider = false
  end
  -- Do not use code actions from pylsp since they are slow for now.
  if client.name == 'pylsp' then
    client.server_capabilities.codeActionProvider = false
  end
  if client.name == 'yamlls' then
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    -- If file name ends with .template.yaml, then we disable yamlls diagnostics since jinja templates cannot be parsed correctly.
    local template_yaml_extension = ".template.yaml"
    if file_name:sub(- #template_yaml_extension) == template_yaml_extension then
      client.handlers["textDocument/publishDiagnostics"] = function() end
    end
  end
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>lr', vim.lsp.buf.rename, '[L]anguage [R]ename]')
  nmap('<leader>la', require('actions-preview').code_actions, '[L]anguage [A]ction')

  nmap('gd',
    function()
      require('trouble').open('lsp_definitions')
    end,
    '[G]oto [D]efinition'
  )
  -- The fname option here is not good enough.
  -- TODO Find a way to display path in a smart way.
  nmap('gr',
    function()
      require('trouble').open('lsp_references')
    end,
    '[G]oto [R]eferences'
  )
  nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ls', require('telescope.builtin').lsp_document_symbols, '[L]anguage [S]ymbols')
  nmap('<leader>lS', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Workspace Symbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  vim.keymap.set({ 'n', 'i' }, '<C-s>',
    function()
      vim.lsp.buf.signature_help()
    end,
    { desc = 'LSP: Signature Documentation', buffer = bufnr }
  )
  if client.server_capabilities.inlayHintProvider then
    vim.keymap.set({ 'n', 'i' }, '<C-i>',
      function()
        vim.lsp.inlay_hint(bufnr)
      end,
      { desc = 'LSP: Signature Documentation', buffer = bufnr }
    )
  end

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

  -- Create a command `:Format` local to the LSP buffer
  vim.keymap.set({ 'n', 'v', }, '<leader>lf',
    function()
      format_go_imports(bufnr)
      fix_ruff_errors(bufnr)
      vim.lsp.buf.format({
        filter = function(format_client)
          -- Do not request typescript-language-server for formatting.
          return format_client.name ~= "tsserver"
        end,
        bufnr = bufnr,
        async = true,
      })
    end,
    {
      desc = "LSP: Format buffer",
      buffer = bufnr,
    }
  )
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client == nil then
      return
    end
    on_attach(client, args.buf)
  end
})

---@type LazyPluginSpec
return {
  -- LSP Configuration & Plugins
  'neovim/nvim-lspconfig',
  dependencies = {
    -- Automatically install LSPs to stdpath for neovim
    { 'williamboman/mason.nvim', config = true },
    'williamboman/mason-lspconfig.nvim',

    -- Useful status updates for LSP
    -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
    { 'j-hui/fidget.nvim',       tag = 'legacy', opts = {} },

    -- Additional lua configuration, makes nvim stuff amazing!
    'folke/neodev.nvim',
  },
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    VENV_PATH = os.getenv('HOME') .. "/.local/share/nvim/mason/packages/python-lsp-server/venv"
    -- Enable the following language servers
    -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    ---@type table<string, lspconfig.Config>
    local servers = {
      clangd = {
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
      },
      gopls = {},
      rust_analyzer = {},
      pylyzer = {
        enabled = false,
      },
      -- Faster than pyright.
      -- Would use pylyzer once it's more feature rich (doesn't support local imports yet).
      pylsp = {
        cmd = { "pylsp", "--log-file=/tmp/pylsp.log", },
        pylsp = {
          plugins = {
            jedi = {
              extra_paths = {
                "bazel-out/k8-fastbuild/bin",
              },
            },
            mccabe = {
              enabled = false,
            },
            pyflakes = {
              enabled = false,
            },
            -- Use black for formatting.
            black = {
              enabled = true,
            },
            yapf = {
              enabled = false,
            },
            autopep8 = {
              enabled = false,
            },
            pycodestyle = {
              enabled = false,
            },
            pylint = {
              enabled = true,
              args = {
                '--disable=invalid-name,missing-module-docstring,wrong-import-position,unused-argument,too-few-public-methods,unused-import,logging-fstring-interpolation,wrong-import-order,consider-using-f-string',
                '--max-line-length=120',
                '--source-root=bazel-out/k8-fastbuild/bin',
              },
              -- Enables pylint to run in live mode.
              executable = VENV_PATH .. "/bin/pylint",
            },
            pylsp_mypy = {
              enabled = true,
              live_mode = true,
              report_progress = true,
              -- Currently using a fork of pylsp-mypy to support venv and MYPYPATH.
              -- https://github.com/PeterCardenas/pylsp-mypy
              venv_path = VENV_PATH,
              relative_mypy_path = "bazel-out/k8-fastbuild/bin",
            },
          }
        }
      },
      pyright = {
        enabled = false,
      },
      -- Prefer to use nogo, but there is not language server for it yet.
      golangci_lint_ls = {
        init_options = {
          command = { 'golangci-lint', 'run', '--out-format', 'json', '--disable-all', '--enable',
            'errcheck,ineffassign,unused' },
        },
      },
      ruff_lsp = {},
      tsserver = {
        cmd_env = {
          NODE_OPTIONS = "--max-old-space-size=6144",
        },
      },
      eslint = {
        cmd_env = {
          NODE_OPTIONS = "--max-old-space-size=6144",
        },
      },
      stylelint_lsp = {
        filetypes = { "css", "scss" },
        stylelintplus = {
          autoFixOnFormat = true,
        }
      },
      lua_ls = {
        Lua = {
          workspace = { checkThirdParty = false },
          telemetry = { enable = false },
        },
      },
    }

    -- Setup neovim lua configuration
    -- Load plugins when editing overall configuration.
    require('neodev').setup({
      override = function(root_dir, library)
        if root_dir:find(".local/share/chezmoi", 1, true) ~= nil then
          library.enabled = true
          library.plugins = true
          library.runtime = true
          library.types = true
        end
      end,
    })

    -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

    -- Ensure the servers above are installed
    local mason_lspconfig = require 'mason-lspconfig'

    mason_lspconfig.setup({
      ensure_installed = vim.tbl_keys(servers),
    })

    -- Setup language servers found locally.
    -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    ---@type table<string, lspconfig.Config>
    local custom_servers = {
      pls = {
        enabled = false,
        cmd = { "protobuf-ls", "server", "--mode", "stdio", },
        filetypes = { "proto" },
        default_config = {
          root_dir = require('lspconfig.util').root_pattern(".git"),
        }
      },
      fishls = {
        enabled = false,
        cmd = { "fish-ls", "--stdio" },
        filetypes = { "fish" },
        default_config = {
          root_dir = require('lspconfig.util').root_pattern(".git"),
        }
      },
      valels = {
        cmd = { "vale-ls" },
        filetypes = { "markdown", "text", "dosini", "yaml" },
        default_config = {
          root_dir = require('lspconfig.util').root_pattern(".vale.ini"),
        }
      },
    }
    for server_name, server_config in pairs(custom_servers) do
      if server_config.enabled == false then
        goto continue
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
      ::continue::
    end

    mason_lspconfig.setup_handlers({
      function(server_name)
        if servers[server_name] and servers[server_name].enabled == false then
          return
        end
        ---@type lsp.ClientCapabilities
        local server_capabilities = capabilities
        if server_name == 'clangd' then
          ---@type lsp.ClientCapabilities
          local clangd_overrides = {
            offsetEncoding = { 'utf-16' },
            general = {
              positionEncodings = { 'utf-16' },
            }
          }
          server_capabilities = vim.tbl_extend('force', server_capabilities, clangd_overrides)
        end
        require('lspconfig')[server_name].setup({
          capabilities = server_capabilities,
          settings = servers[server_name],
          filetypes = (servers[server_name] or {}).filetypes,
          cmd = (servers[server_name] or {}).cmd,
          cmd_env = (servers[server_name] or {}).cmd_env,
          init_options = (servers[server_name] or {}).init_options,
        })
      end
    })
  end,
}
