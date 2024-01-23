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
      },
      gopls = {},
      rust_analyzer = {},
      -- Prefer to use nogo, but there is not language server for it yet.
      golangci_lint_ls = {
        init_options = {
          command = { 'golangci-lint', 'run', '--out-format', 'json', '--disable-all', '--enable', 'errcheck,ineffassign,unused' },
        },
      },
      tsserver = {
        enabled = require('utils.config').tsserver_enabled,
        cmd_env = {
          NODE_OPTIONS = '--max-old-space-size=6144',
        },
      },
      eslint = {
        cmd_env = {
          NODE_OPTIONS = '--max-old-space-size=8192',
        },
      },
      stylelint_lsp = {
        filetypes = { 'css', 'scss' },
        stylelintplus = {
          autoFixOnFormat = true,
        },
      },
      lua_ls = {
        Lua = {
          workspace = { checkThirdParty = false },
          telemetry = { enable = false },
          hint = { enable = true },
        },
      },
    }
    local python_lsp_config = require('plugins.lsp.python').python_lsp_config()
    servers = vim.tbl_extend('force', servers, python_lsp_config)

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
    capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

    -- Setup language servers found locally.
    require('plugins.lsp.local').setup(capabilities)
    -- Setup specific autocmds.
    require('plugins.lsp.python').setup()
    -- Setup servers that are in Mason but not in mason-lspconfig.
    -- TODO: Move this to servers table when the following PR is merged:
    -- https://github.com/williamboman/mason-lspconfig.nvim/pull/350
    require('lspconfig').bzl.setup({
      capabilities = capabilities,
      filetypes = { 'bzl', 'Bazelrc' },
    })

    -- Ensure the servers above are installed
    local mason_lspconfig = require('mason-lspconfig')

    mason_lspconfig.setup({
      ensure_installed = vim.tbl_keys(servers),
    })

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
            },
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
      end,
    })
  end,
}
