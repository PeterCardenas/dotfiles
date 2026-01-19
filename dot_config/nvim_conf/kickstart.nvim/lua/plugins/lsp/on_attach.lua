local File = require('utils.file')
local Config = require('utils.config')
local LspMethod = vim.lsp.protocol.Methods

local M = {}

local semantic_tokens_group = vim.api.nvim_create_augroup('vim_lsp_semantic_tokens_rewriter', { clear = true })

---Configures a language server after it attaches to a buffer.
---@param client vim.lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local git_root = File.get_git_root()
  local is_in_git_root = git_root ~= nil and File.file_in_directory(filename, git_root)

  if not is_in_git_root then
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end

  ---@param keys string
  ---@param action fun(): nil
  ---@param desc string
  local function nmap(keys, action, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, action, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>lr', function()
    vim.lsp.buf.rename()
  end, '[L]anguage [R]ename')
  nmap('<leader>la', function()
    require('fzf-lua.providers.lsp').code_actions({
      winopts = { height = 0.33, width = 1, relative = 'cursor', row = 1, backdrop = 100, preview = {
        layout = 'horizontal',
      } },
      toggle_behavior = 'extend',
      silent = true,
      previewer = 'codeaction_native',
    })
  end, '[L]anguage [A]ction')

  nmap('gd', function()
    require('trouble').open('lsp_definitions')
    -- require('fzf-lua.providers.lsp').definitions({
    --   winopts = { height = 0.5, width = 1, relative = 'cursor', backdrop = 100, preview = {
    --     layout = 'vertical',
    --   } },
    --   toggle_behavior = 'extend',
    -- })
  end, '[G]oto [D]efinition')
  nmap('gr', function()
    require('trouble').open('lsp_references')
    -- TODO: width 1 doesn't take up the whole screen width

    -- require('fzf-lua.providers.lsp').references({
    --   winopts = { height = 0.5, width = 1, relative = 'cursor', backdrop = 100, preview = {
    --     layout = 'vertical',
    --   } },
    --   includeDeclaration = false,
    --   toggle_behavior = 'extend',
    -- })
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
    require('fzf-lua.providers.lsp').live_workspace_symbols()
  end, 'Workspace Symbols')

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
  pcall(vim.keymap.del, 'n', 'grt')

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

  if client.name == 'rust-analyzer' then
    nmap('K', function()
      require('rustaceanvim.hover_actions').hover_actions()
    end, 'Hover Documentation')
  else
    nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
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
