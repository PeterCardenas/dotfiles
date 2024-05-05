local M = {}

local LspMethod = vim.lsp.protocol.Methods

--  Configures a language server after it attaches to a buffer.
---@param client lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
  if client.name == 'yamlls' then
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    -- If file name ends with .template.yaml, then we disable yamlls diagnostics since jinja templates cannot be parsed correctly.
    local template_yaml_extension = '.template.yaml'
    if file_name:sub(-#template_yaml_extension) == template_yaml_extension then
      client.handlers[LspMethod.textDocument_publishDiagnostics] = function() end
    end
  end
  if client.name == 'lua_ls' then
    -- Defer to stylua for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'cssls' then
    -- Defer to stylelint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'jsonls' then
    -- Defer to jq for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'gopls' then
    if not client.server_capabilities.semanticTokensProvider then
      local semantic = client.config.capabilities.textDocument.semanticTokens
      if semantic then
        client.server_capabilities.semanticTokensProvider = {
          full = true,
          legend = {
            tokenTypes = semantic.tokenTypes,
            tokenModifiers = semantic.tokenModifiers,
          },
          range = true,
        }
      end
    end
  end

  local function nmap(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  vim.keymap.set('n', '<leader>lr', function()
    return ':IncRename ' .. vim.fn.expand('<cword>')
  end, { expr = true, desc = '[L]anguage [R]ename' })
  nmap('<leader>la', function()
    require('actions-preview').code_actions()
  end, '[L]anguage [A]ction')

  nmap('gd', function()
    require('trouble').open('lsp_definitions')
  end, '[G]oto [D]efinition')
  -- The fname option here is not good enough.
  -- TODO Find a way to display path in a smart way.
  nmap('gr', function()
    require('trouble').open('lsp_references')
  end, '[G]oto [R]eferences')
  nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ls', require('telescope.builtin').lsp_document_symbols, '[L]anguage [S]ymbols')
  nmap('<leader>lS', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Workspace Symbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    vim.lsp.buf.signature_help()
  end, { desc = 'LSP: Signature Documentation', buffer = bufnr })
  if client.server_capabilities.inlayHintProvider then
    -- Enable inlay hints by default.
    require('vim.lsp.inlay_hint')(bufnr, true)
    vim.keymap.set({ 'n', 'i' }, '<C-i>', function()
      vim.lsp.inlay_hint(bufnr)
    end, { desc = 'LSP: Signature Documentation', buffer = bufnr })
  end

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

  -- Create a command `:Format` local to the LSP buffer
  vim.keymap.set({ 'n', 'v' }, '<leader>lf', function()
    require('plugins.lsp.format').format(bufnr)
  end, {
    desc = 'LSP: Format buffer',
    buffer = bufnr,
  })
  require('plugins.lsp.format').setup_formatting_diagnostic(bufnr)
end

return M
