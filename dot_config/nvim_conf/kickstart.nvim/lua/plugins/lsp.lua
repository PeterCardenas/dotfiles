-- [[ Configure LSP ]]

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
    {
      'j-hui/fidget.nvim',
      tag = 'legacy',
      config = function()
        require('fidget').setup({
          window = {
            winblend = 0,
          },
        })
      end,
    },

    -- Additional lua configuration, makes nvim stuff amazing!
    'folke/neodev.nvim',
  },
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    -- Enable the following language servers
    -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    ---@type table<string, lspconfig.Config>
    local servers = {
      clangd = {
        filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
        capabilities = {
          offsetEncoding = { 'utf-16' },
          general = {
            positionEncodings = { 'utf-16' },
          },
        },
      },
      gopls = {},
      rust_analyzer = {},
      -- Prefer to use nogo, but there is not language server for it yet.
      golangci_lint_ls = {
        enabled = not require("utils.config").GOPLS_WORKAROUND_ENABLED,
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
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            hint = { enable = true },
            library = vim.tbl_extend('keep', {
              vim.fn.expand('$VIMRUNTIME/lua'),
              vim.fn.stdpath("config") .. '/lua',
            },
              vim.api.nvim_get_runtime_file('', true)
            ),
          },
        },
      },
      bzl = {
        filetypes = { 'bzl', 'Bazelrc' },
      },
    }
    local python_lsp_config = require('plugins.lsp.python').python_lsp_config()
    servers = require('utils.table').merge_tables(servers, python_lsp_config)

    -- Setup neovim lua configuration
    -- Load plugins when editing overall configuration.
    require('neodev').setup({
      ---@param root_dir string
      override = function(root_dir, library)
        if root_dir:find('.local/share/chezmoi', 1, true) ~= nil then
          library.enabled = true
          library.plugins = true
          library.runtime = true
          library.types = true
        end
      end,
    })

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
      ensure_installed = vim.tbl_keys(servers),
    })

    mason_lspconfig.setup_handlers({
      function(server_name)
        local server_config = servers[server_name] or {}
        if server_config.enabled == false then
          return
        end
        server_config.capabilities = require('utils.table').merge_tables(capabilities, server_config.capabilities or {})
        require('lspconfig')[server_name].setup(server_config)
      end,
    })
  end,
}
