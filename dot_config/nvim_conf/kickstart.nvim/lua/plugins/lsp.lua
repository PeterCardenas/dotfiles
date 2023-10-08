-- [[ Configure LSP ]]
--  This function gets run when an LSP connects to a particular buffer.
---@param client lsp.Client
---@param bufnr integer
local on_attach = function(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>lr', vim.lsp.buf.rename, '[L]anguage [R]ename]')
  nmap('<leader>la', vim.lsp.buf.code_action, '[L]anguage [A]ction')

  nmap('gd',
    function()
      require('telescope.builtin').lsp_definitions()
    end,
    '[G]oto [D]efinition'
  )
  nmap('gr',
    function()
      require('telescope.builtin').lsp_references()
    end,
    '[G]oto [R]eferences'
  )
  nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ls', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>lS', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  vim.keymap.set({ 'n', 'i' }, '<C-k>',
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
  nmap('<leader>lf', function()
    vim.lsp.buf.format({
      filter = function(format_client)
        -- Do not request typescript-language-server for formatting.
        return format_client.name ~= "tsserver"
      end
    })
  end, "Format buffer")
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
    { 'j-hui/fidget.nvim', tag = 'legacy', opts = {} },

    -- Additional lua configuration, makes nvim stuff amazing!
    'folke/neodev.nvim',
  },
  event = "BufEnter",
  config = function()
    -- Enable the following language servers
    -- Type inferred from https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    ---@type table<string, lspconfig.Config>
    local servers = {
      clangd = {},
      gopls = {},
      pyright = {},
      rust_analyzer = {},
      tsserver = {},
      eslint = {},
      stylelint_lsp = {
        filetypes = { "css", "scss" },
        settings = {
          stylelintplus = {
            autoFixOnFormat = true,
          }
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
    require('neodev').setup()

    -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

    -- Ensure the servers above are installed
    local mason_lspconfig = require 'mason-lspconfig'

    mason_lspconfig.setup {
      ensure_installed = vim.tbl_keys(servers),
    }

    mason_lspconfig.setup_handlers {
      function(server_name)
        local server_capabilities = capabilities
        if server_name == 'clangd' then
          server_capabilities = vim.tbl_extend('force', server_capabilities, {
            offsetEncoding = { 'utf-16' },
            general = {
              positionEncodings = { 'utf-16' },
            }
          })
        end
        require('lspconfig')[server_name].setup({
          capabilities = server_capabilities,
          settings = servers[server_name],
          filetypes = (servers[server_name] or {}).filetypes,
        })
      end
    }
  end,
}
