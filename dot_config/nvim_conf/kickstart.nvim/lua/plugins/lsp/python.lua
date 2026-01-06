local Config = require('utils.config')
local Spinner = require('utils.spinner')
local Shell = require('utils.shell')
local File = require('utils.file')
local Async = require('utils.async')
local M = {}
local LspMethod = vim.lsp.protocol.Methods

local enable_pyright = not Config.USE_JEDI
M.GEN_FILES_PATH = 'bazel-out/k8-fastbuild/bin'

---@return LspTogglableConfig
local function pyright_config()
  ---@type LspTogglableConfig
  local config = {
    enabled = enable_pyright and not Config.USE_ZUBAN,
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
    -- TODO: Add code action handle for adding an import. Currently this is done automatically via the format keybind.
    handlers = {
      ---@param _ lsp.ResponseError
      ---@param result lsp.PublishDiagnosticsParams
      ---@param ctx lsp.HandlerContext
      ---@param _config table
      [LspMethod.textDocument_publishDiagnostics] = function(_, result, ctx, _config)
        local diagnostics = result.diagnostics
        ---@type lsp.Diagnostic[]
        local filtered_diagnostics = {}
        for _, diagnostic in ipairs(diagnostics) do
          local should_filter = true
          -- TODO: Remove this when pyright can read venvPath
          if
            diagnostic.code == 'reportMissingImports'
            or diagnostic.code == 'reportAttributeAccessIssue'
            or diagnostic.code == 'reportMissingModuleSource'
            -- False positive by not inferring type from default arguments
            or diagnostic.code == 'reportArgumentType'
            -- Mypy handles this correctly
            or diagnostic.code == 'reportInvalidTypeForm'
          then
            should_filter = false
          end
          local message = diagnostic.message
          if type(message) == 'string' then
            if message:match('^"_[%w_]+" is not accessed$') then
              should_filter = false
            end
          end
          if should_filter then
            filtered_diagnostics[#filtered_diagnostics + 1] = diagnostic
          end
        end
        result.diagnostics = filtered_diagnostics
        return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx)
      end,
    },
    settings = {
      python = {
        analysis = {
          autoImportCompletions = true,
          extraPaths = {
            M.GEN_FILES_PATH,
          },
          diagnosticMode = 'workspace',
          typeCheckingMode = 'off',
        },
      },
    },
  }
  return config
end

local function pylsp_config()
  -- The following are rules that we want from pylint, but are not supported elsewhere.
  -- 'trailing-newlines'
  ---@type LspTogglableConfig
  local config = {
    enabled = not Config.USE_ZUBAN,
    settings = {
      pylsp = {
        plugins = {
          jedi = {
            enabled = true,
            prioritize_extra_paths = true,
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
  }

  return config
end

---@return LspTogglableConfig
local function get_ruff_lsp_config()
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

  ---@type LspTogglableConfig
  local config = {
    -- TODO: Try conform for formatting instead since getting issues with the formatter not using the right version.
    init_options = {
      settings = {
        args = ruff_args,
      },
    },
    handlers = {
      ---@param _ lsp.ResponseError
      ---@param result lsp.PublishDiagnosticsParams
      ---@param ctx lsp.HandlerContext
      ---@param _config table
      [LspMethod.textDocument_publishDiagnostics] = function(_, result, ctx, _config)
        -- Change severity of ruff warnings to errors.
        for _, diagnostic in ipairs(result.diagnostics) do
          diagnostic.severity = vim.lsp.protocol.DiagnosticSeverity.Error
        end
        return vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx)
      end,
    },
  }
  return config
end

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

---@param filepath string
---@return string|nil
function M.find_lsp_root(filepath)
  if not File.file_exists(filepath) then
    return nil
  end
  local targets = { 'pyproject.toml', 'setup.py', 'requirements.txt', '.git' }
  local root = nil
  for _, target in ipairs(targets) do
    local candidate = File.get_ancestor_dir(target, filepath)
    if candidate then
      if not root or (#candidate > #root) then
        root = candidate
      end
    end
  end
  return root
end

---@async
---@param override_requirements_path? string
---@param force_python_version? string
---@param extra_index_url? string
---Installs python dependencies according to requirements.txt in the workspace.
function M.maybe_install_python_dependencies(override_requirements_path, force_python_version, extra_index_url)
  local cwd = File.get_cwd()
  -- Find a Python file in the current directory
  local success, output = Shell.async_cmd('rg', { '--files', '-g', '*.py' })
  if not success or #output == 0 then
    return
  end
  if vim.fn.executable('uv') == 0 then
    vim.notify('uv not found, cannot install python dependencies', vim.log.levels.ERROR)
    return
  end
  local found_file = cwd .. '/' .. output[1]

  local lsp_root = M.find_lsp_root(found_file)
  if not lsp_root then
    return
  end
  local venv_path = lsp_root .. '/.venv'
  local requirements_path ---@type string
  if override_requirements_path and File.file_exists(override_requirements_path) then
    requirements_path = override_requirements_path
  elseif File.file_exists(lsp_root .. '/requirements.txt') then
    requirements_path = lsp_root .. '/requirements.txt'
  else
    return
  end
  local timer = Spinner.create_timer()
  local spinner = Spinner.create_spinner({
    '▰▱▱▱',
    '▰▰▱▱',
    '▰▰▰▱',
    '▰▰▰▰',
    '▰▱▱▱',
  })
  local cleared = false
  timer.start(function()
    if cleared then
      return
    end
    require('fidget').notify(' ', vim.log.levels.WARN, {
      group = 'install_python_deps',
      key = 'install_python_deps',
      annote = spinner() .. ' Installing python dependencies...',
      ttl = math.huge,
    })
  end)
  local function clear_fidget()
    cleared = true
    timer.stop()
    require('fidget').notification.remove('install_python_deps', 'install_python_deps')
  end
  if not File.file_exists(venv_path) or (force_python_version and not File.file_exists(venv_path .. '/lib/python' .. force_python_version)) then
    local venv_args = { 'venv', '--allow-python-downloads', '--managed-python' }
    if force_python_version then
      venv_args[#venv_args + 1] = '--python'
      venv_args[#venv_args + 1] = force_python_version
    end
    venv_args[#venv_args + 1] = venv_path
    success, output = Shell.async_cmd('uv', venv_args, nil)
    if not success then
      vim.schedule(function()
        vim.notify('Failed to start virtualenv:\n' .. table.concat(output, '\n'), vim.log.levels.ERROR)
        clear_fidget()
      end)
      return
    end
  end
  local index_flag = ''
  if extra_index_url then
    index_flag = '--index ' .. extra_index_url .. ' '
  end
  success, output = Shell.async_cmd('bash', { '-c', 'source ' .. venv_path .. '/bin/activate && uv pip sync ' .. index_flag .. requirements_path })
  if not success then
    vim.schedule(function()
      vim.notify('Failed to install python dependencies:\n' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      clear_fidget()
    end)
    return
  end
  success, output = Shell.async_cmd('bash', { '-c', 'source ' .. venv_path .. '/bin/activate && uv pip install python-lsp-server==1.13.0 mypy pylint' })
  if not success then
    vim.schedule(function()
      vim.notify('Failed to install python tooling:\n' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      clear_fidget()
    end)
    return
  end
  vim.schedule(function()
    clear_fidget()
    require('fidget').notify(' ', vim.log.levels.INFO, {
      group = 'install_python_deps',
      key = 'install_python_deps',
      annote = '✅ Installed python dependencies',
      ttl = 3,
    })
    local config = pylsp_config()
    if config.enabled == false then
      return
    end
    config.cmd = { venv_path .. '/bin/pylsp' }
    local existing_config = vim.lsp.config['pylsp'] or {}
    local merged_config = vim.tbl_extend('force', existing_config, config)
    vim.lsp.config('pylsp', merged_config)
    -- Restart pylsp with correct config.
    vim.lsp.enable('pylsp', false)
    vim.lsp.enable('pylsp')
  end)
end

function M.setup()
  Async.void(function() ---@async
    M.maybe_install_python_dependencies()
  end)
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
  -- Often redundant
  'fixme',
  -- Line length checking is most often just annoying.
  'line-too-long',
  -- Below have been delegated to mypy.
  'too-many-function-args',
  'undefined-variable',
  'no-member',
  'c-extension-no-member',
  -- Below have been delegated to ruff.
  'unused-variable',
  'trailing-whitespace',
  'missing-function-docstring',
  'missing-class-docstring',
  'f-string-without-interpolation',
  'too-many-branches',
  'protected-access',
  'unspecified-encoding',
  'unnecessary-comprehension',
  'unnecessary-lambda',
  'bare-except',
  'consider-using-get',
  'unexpected-special-method-signature',
  'broad-exception-raised',
  'cell-var-from-loop',
  'logging-too-few-args',
  'logging-too-many-args',
}

---@param servers table<string, LspTogglableConfig>
function M.add_config(servers)
  servers.pylyzer = {
    enabled = false,
  }
  servers.basedpyright = {
    enabled = false,
  }
  servers.pyright = pyright_config()
  servers.pylsp = pylsp_config()
  servers.ruff_lsp = get_ruff_lsp_config()
  servers.zuban = { enabled = Config.USE_ZUBAN, cmd_env = { ZUBAN_LOG_FILE = '/tmp/zuban.log', ZUBAN_LOG = 'debug' } }
end

return M
