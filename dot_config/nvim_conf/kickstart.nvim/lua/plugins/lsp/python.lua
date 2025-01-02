local M = {}
local LspMethod = vim.lsp.protocol.Methods

local enable_pyright = not require('utils.config').USE_JEDI
M.GEN_FILES_PATH = 'bazel-out/k8-fastbuild/bin'

--  Configures a language server after it attaches to a buffer.
---@param client vim.lsp.Client
---@param _ integer buffer number
local function on_attach(client, _)
  if client.name == 'ruff_lsp' then
    -- Defer to pylsp jedi plugin for hover documentation.
    client.server_capabilities.hoverProvider = false
  end
  if client.name == 'pyright' then
    -- TODO: Use pyright instead of jedi for all language features when venvPath works.
    client.server_capabilities.definitionProvider = false
    client.server_capabilities.hoverProvider = false
  end
  if client.name == 'pylsp' then
    -- Do not use code actions from pylsp since they are slow for now.
    client.server_capabilities.codeActionProvider = false
    -- Disable language features that would be redundant with pyright.
    client.server_capabilities.documentSymbolProvider = not enable_pyright
    client.server_capabilities.referencesProvider = not enable_pyright
    client.server_capabilities.renameProvider = not enable_pyright
  end
end

function M.setup()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('PythonConfig', { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = args.buf })
      if client == nil or filetype ~= 'python' then
        return
      end
      on_attach(client, args.buf)
    end,
  })
end

M.VENV_PATH = os.getenv('HOME') .. '/.local/share/nvim/mason/packages/python-lsp-server/venv'
-- TODO(@PeterCardenas): Replace all useful pylint rules with ruff rules.
M.DISABLED_PYLINT_RULES = {
  'invalid-name',
  'missing-module-docstring',
  'wrong-import-position',
  'unused-argument',
  'too-few-public-methods',
  'unused-import',
  'logging-fstring-interpolation',
  'wrong-import-order',
  'consider-using-f-string',
  -- Line length checking is most often just annoying.
  'line-too-long',
  -- Below have been delegated to mypy.
  'too-many-function-args',
  'undefined-variable',
  'no-member',
  -- Below have been delegated to ruff.
  'trailing-whitespace',
  'missing-function-docstring',
  'missing-class-docstring',
  'f-string-without-interpolation',
  'too-many-branches',
  'protected-access',
  'unspecified-encoding',
  'unnecessary-comprehension',
  'bare-except',
  'consider-using-get',
  'unexpected-special-method-signature',
  'broad-exception-raised',
  'cell-var-from-loop',
  'logging-too-few-args',
  'logging-too-many-args',
}

---@return table<string, lspconfig.Config>
local function pylsp_config()
  -- The following are rules that we want from pylint, but are not supported elsewhere.
  -- 'trailing-newlines'
  return {
    pylsp = {
      settings = {
        pylsp = {
          plugins = {
            jedi = {
              enabled = true,
              extra_paths = {
                M.GEN_FILES_PATH,
              },
            },
            pylint = {
              enabled = false,
            },
            pylsp_mypy = {
              enabled = false,
            },
            -- Disable other default formatters and linters in favor of ruff and pylint.
            black = {
              enabled = false,
            },
            mccabe = {
              enabled = false,
            },
            pyflakes = {
              enabled = false,
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
          },
        },
      },
    },
  }
end

---@return table<string, lspconfig.Config>
local function ruff_lsp_config()
  local additional_rules = {
    'D', -- pydocstyle: https://docs.astral.sh/ruff/rules/#pydocstyle-d
    'W', -- pycodestyle warnings: https://docs.astral.sh/ruff/rules/#warning-w
    'PLR0912', -- too-many-branches
    'T201', -- print
    'SLF001', -- private-member-access
    'PLW1514', -- unspecified-encoding
    'C416', -- unnecessary-comprehension
    'SIM401', -- if-else-block-instead-of-dict-get
    'PLE0302', --unexpected-special-method-signature
    'TRY002', -- raise-vanilla-class
    'B023', -- function-uses-loop-variable
    'PLE1206', -- logging-too-few-args
    'PLE1205', -- logging-too-many-args
  }
  local ignored_rules = {
    'W191', -- tab-indentation https://docs.astral.sh/ruff/rules/tab-indentation/
    'E203', -- whitespace before ':' https://docs.astral.sh/ruff/rules/whitespace-before-colon/, this comes up with false positives
  }
  local used_in_repo = {
    'W605', -- invalid escape sequence https://docs.astral.sh/ruff/rules/invalid-escape-sequence/
    'W293', -- trailing whitespace https://docs.astral.sh/ruff/rules/trailing-whitespace/
    'E251', -- unexpected spaces around keyword / parameter equals https://docs.astral.sh/ruff/rules/unexpected-spaces-around-keyword-parameter-equals/
  }
  local ruff_args = {
    -- Enable preview mode for some additional rules.
    '--preview',
    '--extend-select=' .. table.concat(additional_rules, ','),
    '--ignore=' .. table.concat(ignored_rules, ','),
    -- Do not fix selected rules to minimize diff.
    '--unfixable=' .. table.concat(additional_rules, ','),
    -- Re-enable rules that are used in codebase.
    '--extend-fixable=' .. table.concat(used_in_repo, ','),
  }
  -- TODO(PeterPCardenas): Fork https://github.com/astral-sh/ruff-lsp
  -- Add support to adding rules without changing how the codebase selects and fixes rules.
  return {
    ruff_lsp = {
      init_options = {
        settings = {
          args = ruff_args,
        },
      },
    },
  }
end

---@return table<string, lspconfig.Config>
function M.python_lsp_config()
  ---@type table<string, lspconfig.Config>
  local server_configs = {
    -- Fastest lsp, but not feature rich enough.
    pylyzer = {
      enabled = false,
    },
    -- Feature rich, but slowest lsp.
    pyright = {
      enabled = enable_pyright,
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
      -- Use for debugging pyright.
      -- cmd = { os.getenv('HOME') .. '/thirdparty/pyright/packages/pyright/langserver.index.js', '--stdio' },
      handlers = {
        ---@param _ lsp.ResponseError
        ---@param result lsp.PublishDiagnosticsParams
        ---@param ctx lsp.HandlerContext
        ---@param config table
        [LspMethod.textDocument_publishDiagnostics] = function(_, result, ctx, config)
          local diagnostics = result.diagnostics
          local filtered_diagnostics = {}
          for _, diagnostic in ipairs(diagnostics) do
            local should_filter = true
            -- TODO: Remove this when pyright can read venvPath
            if
              diagnostic.code == 'reportMissingImports'
              or diagnostic.code == 'reportAttributeAccessIssue'
              or diagnostic.code == 'reportMissingModuleSource'
            then
              should_filter = false
            end
            local message = diagnostic.message
            if type(message) == 'string' then
              if message:match('^"_%w+" is not accessed$') then
                should_filter = false
              end
            end
            if should_filter then
              table.insert(filtered_diagnostics, diagnostic)
            end
          end
          result.diagnostics = filtered_diagnostics
          return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
        end,
      },
      settings = {
        python = {
          analysis = {
            autoImportCompletions = true,
            extraPaths = {
              M.GEN_FILES_PATH,
            },
            -- TODO(@PeterPCardenas): Re-enable this when pyright is more performant.
            -- diagnosticMode = 'workspace',
            typeCheckingMode = 'off',
          },
        },
      },
    },
  }
  local ruff_configs = ruff_lsp_config()
  server_configs = vim.tbl_extend('force', server_configs, ruff_configs)
  -- Fastest lsp, but linting/formatting will be moved to ruff.
  local pylsp_configs = pylsp_config()
  server_configs = vim.tbl_extend('force', server_configs, pylsp_configs)
  return server_configs
end

return M
