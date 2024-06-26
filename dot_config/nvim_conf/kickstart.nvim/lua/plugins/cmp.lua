---@type LazyPluginSpec
return {
  -- Autocompletion
  'hrsh7th/nvim-cmp',
  dependencies = {
    -- Snippet Engine & its associated nvim-cmp source
    'L3MON4D3/LuaSnip',
    'saadparwaiz1/cmp_luasnip',

    -- Adds LSP completion capabilities
    'hrsh7th/cmp-nvim-lsp',

    -- Adds a number of user-friendly snippets
    'rafamadriz/friendly-snippets',

    -- Git/GitHub completion
    'petertriho/cmp-git',

    -- Emoji completion
    'hrsh7th/cmp-emoji',

    -- Command completion
    'hrsh7th/cmp-cmdline',

    -- Get words from the current buffer
    'hrsh7th/cmp-buffer',

    -- Add completions for fish shell
    'mtoohey31/cmp-fish',
  },
  event = { 'InsertEnter', 'CmdlineEnter' },
  config = function()
    local cmp = require('cmp')
    local luasnip = require('luasnip')
    require('luasnip.loaders.from_vscode').lazy_load()
    luasnip.config.setup({})
    vim.keymap.set({ 'i', 's' }, '<C-n>', function()
      if luasnip.expand_or_jumpable() then
        return luasnip.expand_or_jump()
      end
    end)
    vim.keymap.set({ 'i', 's' }, '<C-p>', function()
      if luasnip.jumpable(-1) then
        return luasnip.jump(-1)
      end
    end)
    require('cmp_git').setup({
      -- Enable completion for all filetypes to get them in comments.
      filetypes = { '*' },
      github = {
        issues = {
          filter = 'subscribed',
        },
      },
      trigger_actions = {
        {
          debug_name = 'github_issues_and_pr',
          trigger_character = '#',
          action = function(sources, trigger_char, callback, params, git_info)
            return sources.github:get_issues_and_prs(callback, git_info, trigger_char)
          end,
        },
        {
          debug_name = 'github_mentions',
          trigger_character = '@',
          action = function(sources, trigger_char, callback, params, git_info)
            return sources.github:get_mentions(callback, git_info, trigger_char)
          end,
        },
      },
    })

    cmp.setup({
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ['<C-j>'] = cmp.mapping.select_next_item(),
        ['<C-k>'] = cmp.mapping.select_prev_item(),
        ['<C-d>'] = cmp.mapping.scroll_docs(-4),
        ['<C-u>'] = cmp.mapping.scroll_docs(4),
        ['<C-Space>'] = cmp.mapping.complete({}),
        ['<CR>'] = cmp.mapping.confirm({
          behavior = cmp.ConfirmBehavior.Replace,
          select = true,
        }),
      }),
      sources = {
        { name = 'git' },
        { name = 'emoji' },
        {
          name = 'nvim_lsp',
          ---@param entry cmp.Entry
          ---@param context cmp.Context
          entry_filter = function(entry, context)
            -- Gets rid of noisy buffer word completion.
            return entry.completion_item.kind ~= require('cmp.types').lsp.CompletionItemKind.Text
          end,
        },
        { name = 'luasnip' },
        { name = 'fish' },
      },
    })

    ---@type cmp.ConfigSchema
    local search_config = {
      mapping = cmp.mapping.preset.cmdline(),
      sources = {
        { name = 'buffer' },
      },
    }
    cmp.setup.cmdline('/', search_config)
    cmp.setup.cmdline('?', search_config)
    cmp.setup.cmdline(':', {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({
        {
          name = 'cmdline',
          option = {
            ignore_cmds = { 'Man', '!' },
          },
        },
      }),
    })
  end,
}
