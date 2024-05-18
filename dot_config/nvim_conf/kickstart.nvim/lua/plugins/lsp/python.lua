local M = {}
local LspMethod = vim.lsp.protocol.Methods

--  Configures a language server after it attaches to a buffer.
---@param client vim.lsp.Client
---@param _ integer buffer number
local function on_attach(client, _)
  if client.name == 'ruff_lsp' then
    -- Defer to pylsp jedi plugin for hover documentation.
    client.server_capabilities.hoverProvider = false
  end
  if client.name == 'pylsp' then
    -- Do not use code actions from pylsp since they are slow for now.
    client.server_capabilities.codeActionProvider = false
    ---@param result lsp.PublishDiagnosticsParams
    ---@param ctx lsp.HandlerContext
    ---@param config any
    client.handlers[LspMethod.textDocument_publishDiagnostics] = function(_, result, ctx, config)
      local diagnostics = result.diagnostics
      local filtered_diagnostics = {}
      for _, diagnostic in ipairs(diagnostics) do
        local should_filter = true
        -- Remove no-name-in-module pylint error for protobuf imports.
        local message = diagnostic.message
        if type(message) == 'string' then
          if diagnostic.source == 'pylint' and diagnostic.code == 'E0611' and message:find('_pb2') then
            should_filter = false
          end
          -- False positive not-callable error for sqlalchemy.func.count.
          if diagnostic.source == 'pylint' and diagnostic.code == 'E1102' and message:find('sqlalchemy.func.count') then
            should_filter = false
          end
        end
        if should_filter then
          table.insert(filtered_diagnostics, diagnostic)
        end
      end
      result.diagnostics = filtered_diagnostics
      return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
    end
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

local enable_pyright = true
local gen_files_path = 'bazel-out/k8-fastbuild/bin'

---@return table<string, lspconfig.Config>
local function pylsp_config()
  VENV_PATH = os.getenv('HOME') .. '/.local/share/nvim/mason/packages/python-lsp-server/venv'
  local disabled_pylint_rules = {
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
  -- The following are rules that we want from pylint, but are not supported elsewhere.
  -- 'trailing-newlines'
  return {
    pylsp = {
      cmd = { 'pylsp', '--log-file=/tmp/pylsp.log' },
      settings = {
        pylsp = {
          plugins = {
            jedi = {
              enabled = not enable_pyright,
              extra_paths = {
                gen_files_path,
              },
            },
            -- TODO(@PeterCardenas): Replace all useful pylint rules with ruff rules.
            pylint = {
              enabled = true,
              args = {
                '--disable=' .. table.concat(disabled_pylint_rules, ','),
              },
              -- Enables pylint to run in live mode.
              -- executable = VENV_PATH .. '/bin/pylint',
              -- TODO(@PeterCardenas): The following is for adding additional paths
              -- for pylint to search for modules. This is made possible by this fork:
              -- https://github.com/PeterCardenas/python-lsp-server
              -- However, I am not enabling this because .pyi files are not taken into
              -- consideration when a .py file with the same module name exists.
              -- Relevant issue: https://github.com/pylint-dev/pylint/issues/6281
              -- extra_paths = {
              --   gen_files_path,
              -- }
            },
            pylsp_mypy = {
              enabled = true,
              live_mode = true,
              report_progress = true,
              -- Currently using a fork of pylsp-mypy to support venv.
              -- https://github.com/PeterCardenas/pylsp-mypy
              venv_path = VENV_PATH,
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
  }
  local used_in_repo = {
    'W605', -- invalid escape sequence https://docs.astral.sh/ruff/rules/invalid-escape-sequence/
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
    -- Currently too slow and laggy in neovim.
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
      settings = {
        python = {
          analysis = {
            autoImportCompletions = true,
            extraPaths = {
              gen_files_path,
            },
            diagnosticMode = 'workspace',
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
