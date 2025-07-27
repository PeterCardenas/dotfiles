local File = require('utils.file')
local Config = require('utils.config')
local LspMethod = vim.lsp.protocol.Methods

local M = {}

local semantic_tokens_group = vim.api.nvim_create_augroup('vim_lsp_semantic_tokens_rewriter', { clear = true })

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
  if client.name == 'ccls' then
    -- Defer to clang-format for formatting.
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

      client:request(method, params, function(err, result, _)
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
  -- TODO: Re-enable when opening ansi_code_helpers.tsx works
  if client.server_capabilities.inlayHintProvider and client.name ~= 'typescript-tools' then
    -- Enable inlay hints by default.
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    vim.keymap.set({ 'n', 'i' }, '<C-i>', function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
    end, { desc = 'LSP: Toggle inlay hints', buffer = bufnr })
  end
  -- Remove default mappings conflicting with gr
  pcall(vim.keymap.del, 'n', 'grn')
  pcall(vim.keymap.del, 'n', 'gri')
  pcall(vim.keymap.del, 'n', 'gra')
  pcall(vim.keymap.del, 'n', 'grr')

  -- Needed to override the inlay hints toggle keymap.
  vim.keymap.set({ 'n', 'i', 's' }, '<Tab>', function()
    local luasnip = require('luasnip')
    if luasnip.expand_or_jumpable() then
      return luasnip.expand_or_jump()
    end
  end, { buffer = bufnr })

  if client:supports_method(LspMethod.textDocument_documentLink) then
    -- Trigger setup
    require('lsplinks')
    nmap('gx', function()
      require('lsplinks').gx()
    end, 'Go to document link under cursor')
  end

  if client.name == 'ts_query_ls' then
    vim.bo[bufnr].omnifunc = 'v:lua.vim.treesitter.query.omnifunc'
  end

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

  -- Do not overwrite todo/fixme highlights with semantic tokens.
  -- Bazelrc files are the exception since there is no syntax highlighting for comments.
  vim.api.nvim_create_autocmd('LspTokenUpdate', {
    buffer = bufnr,
    group = semantic_tokens_group,
    callback = function(args)
      ---@type STTokenRange
      local token = args.data.token
      ---@type integer
      local client_id = args.data.client_id
      local namespace_id = vim.api.nvim_get_namespaces()['nvim.lsp.semantic_tokens:' .. tostring(client_id)]
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace_id, { token.line, token.start_col }, { token.line, token.end_col }, {
        details = true,
        hl_name = true,
      })
      for _, extmark in ipairs(extmarks) do
        ---@type vim.api.keyset.extmark_details?
        local extmark_details = extmark[4]
        local extmark_id = extmark[1]
        if extmark_details ~= nil and extmark_details.hl_group:match('^@lsp%.type%.comment%..*') and client.name ~= 'bazelrc_lsp' then
          vim.api.nvim_buf_del_extmark(bufnr, namespace_id, extmark_id)
        end
      end
    end,
  })
end

return M
