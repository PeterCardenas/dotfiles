local File = require('utils.file')
local Config = require('utils.config')
local LspMethod = vim.lsp.protocol.Methods

local M = {}

---Configures a language server after it attaches to a buffer.
---@param client vim.lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
  if client.name == 'yamlls' then
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    -- If file name ends with template.yaml, then we disable yamlls diagnostics since jinja templates cannot be parsed correctly.
    local template_yaml_extension = 'template.yaml'
    if file_name:sub(-#template_yaml_extension) == template_yaml_extension then
      ---@type lsp.Handler
      client.handlers[LspMethod.textDocument_publishDiagnostics] = function() end
    end
  end
  if client.name == 'lua_ls' then
    -- Defer to stylua for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'emmylua_ls' then
    -- Defer to stylua for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'cssls' then
    -- Defer to stylelint for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'bashls' then
    -- Defer to shfmt for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'jsonls' then
    -- Defer to jq for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'gopls' then
    -- workaround for gopls not supporting semanticTokensProvider
    -- https://github.com/golang/go/issues/54531#issuecomment-1464982242
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
  if client.name == 'clangd' then
    require('clangd_extensions.inlay_hints').setup_autocmd()
  end
  if client.name == 'fish_lsp' then
    -- Defer to fish_indent for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  if client.name == 'bzl' then
    -- Prefer starpls for definition.
    client.server_capabilities.definitionProvider = false
    client.server_capabilities.hoverProvider = false
  end
  if client.name == 'protols' then
    -- Defer to clang-format for formatting.
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end
  -- Setup github issues and PR completion.
  -- This overrides the lsp omnifunc.
  require('octo.completion').setup()
  vim.api.nvim_set_option_value('omnifunc', 'v:lua.octo_omnifunc', { buf = bufnr })

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local git_root = File.get_git_root()
  local is_in_git_root = git_root ~= nil and File.file_in_directory(filename, git_root)

  if client.name == 'starpls' then
    vim.api.nvim_buf_create_user_command(bufnr, 'StarlarkSyntaxTree', function()
      local method = 'starpls/showSyntaxTree'

      local params = {
        textDocument = {
          uri = vim.uri_from_bufnr(bufnr),
        },
      }

      client.request(method, params, function(err, result, _)
        if err then
          vim.print('Error: ' .. err.message)
          return
        end

        vim.print('Starlark syntax tree:', vim.inspect(result):gsub('\\n', '\n'))
      end)
    end, { nargs = 0 })
  end

  if not is_in_git_root then
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end

  ---@param keys string
  ---@param func fun(): nil
  ---@param desc string
  local function nmap(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>lr', function()
    vim.lsp.buf.rename()
  end, '[L]anguage [R]ename')
  nmap('<leader>la', function()
    require('actions-preview').code_actions()
  end, '[L]anguage [A]ction')

  nmap('gd', function()
    require('trouble').open('lsp_definitions')
  end, '[G]oto [D]efinition')
  nmap('gr', function()
    require('trouble').open('lsp_references')
  end, '[G]oto [R]eferences')
  nmap('gI', function()
    require('telescope.builtin').lsp_implementations()
  end, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ls', function()
    if Config.USE_TELESCOPE then
      require('telescope.builtin').lsp_document_symbols()
    else
      require('fzf-lua.providers.lsp').document_symbols({
        winopts = {
          height = 0.9,
          width = 0.85,
        },
      })
    end
  end, '[L]anguage [S]ymbols')
  nmap('<leader>lS', function()
    require('telescope.builtin').lsp_dynamic_workspace_symbols()
  end, 'Workspace Symbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    vim.lsp.buf.signature_help()
  end, { desc = 'LSP: Signature Documentation', buffer = bufnr })
  if client.server_capabilities.inlayHintProvider then
    -- Enable inlay hints by default.
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    vim.keymap.set({ 'n', 'i' }, '<C-i>', function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
    end, { desc = 'LSP: Toggle inlay hints', buffer = bufnr })
  end

  -- Needed to override the inlay hints toggle keymap.
  vim.keymap.set({ 'n', 'i', 's' }, '<Tab>', function()
    local luasnip = require('luasnip')
    if luasnip.expand_or_jumpable() then
      return luasnip.expand_or_jump()
    end
  end, { buffer = bufnr })

  if client.supports_method(LspMethod.textDocument_documentLink) then
    -- Trigger setup
    require('lsplinks')
    nmap('gx', function()
      require('lsplinks').gx()
    end, 'Go to document link under cursor')
  end

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
end

return M
