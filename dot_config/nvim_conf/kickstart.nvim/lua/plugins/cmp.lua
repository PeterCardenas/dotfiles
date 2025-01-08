---@type LazyPluginSpec[]
return {
  {
    -- Adds LSP completion capabilities
    'hrsh7th/cmp-nvim-lsp',
    ft = require('utils.lsp').FT_WITH_LSP,
  },
  {
    -- Adds a number of user-friendly snippets
    'rafamadriz/friendly-snippets',
    event = { 'InsertEnter' },
  },
  {
    'amarakon/nvim-cmp-fonts',
    ft = 'ghostty',
  },
  {
    -- Snippet Engine & its associated nvim-cmp source
    'L3MON4D3/LuaSnip',
    event = { 'InsertEnter' },
    config = function()
      local luasnip = require('luasnip')
      require('luasnip.loaders.from_vscode').lazy_load()
      luasnip.config.setup({})
      vim.keymap.set({ 'n', 'i', 's' }, '<Tab>', function()
        if luasnip.expand_or_jumpable() then
          return luasnip.expand_or_jump()
        end
      end)
      vim.keymap.set({ 'n', 'i', 's' }, '<S-Tab>', function()
        if luasnip.jumpable(-1) then
          return luasnip.jump(-1)
        end
      end)
    end,
  },
  {
    'saadparwaiz1/cmp_luasnip',
    ft = require('utils.lsp').FT_WITH_LSP,
  },
  {
    -- Command completion
    'hrsh7th/cmp-cmdline',
    event = { 'CmdlineEnter' },
  },
  {
    -- Get words from the current buffer
    'hrsh7th/cmp-buffer',
    event = { 'CmdlineEnter' },
  },
  {
    -- Add completions for fish shell
    'mtoohey31/cmp-fish',
    ft = { 'fish' },
  },
  {
    -- Autocompletion
    'hrsh7th/nvim-cmp',
    dependencies = {
      -- Git/GitHub completion
      { 'PeterCardenas/cmp-git', branch = 'working-state' },

      -- Emoji completion
      'hrsh7th/cmp-emoji',

      -- omnifunc completion
      'hrsh7th/cmp-omni',

      -- File path completion
      'https://codeberg.org/FelipeLema/cmp-async-path',
    },
    event = { 'InsertEnter', 'CmdlineEnter' },
    config = function()
      local cmp = require('cmp')
      require('cmp_git').setup({
        -- Enable completion for all filetypes to get them in comments.
        filetypes = { '*' },
        ssh_aliases = {
          ['personal-github.com'] = 'github.com',
          ['work-github.com'] = 'github.com',
        },
        github = {
          issues = {
            filter = 'assigned',
            limit = 100,
          },
          mentions = {
            limit = math.huge,
          },
        },
        trigger_actions = {
          {
            debug_name = 'github_issues',
            trigger_character = '#',
            action = function(sources, trigger_char, callback, _params, git_info)
              return sources.github:get_issues(callback, git_info, trigger_char)
            end,
          },
          {
            debug_name = 'github_mentions',
            trigger_character = '@',
            action = function(sources, trigger_char, callback, _params, git_info)
              return sources.github:get_mentions(callback, git_info, trigger_char)
            end,
          },
        },
      })

      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = {
          ['<Down>'] = {
            i = cmp.mapping.select_next_item({ behavior = require('cmp.types').cmp.SelectBehavior.Select }),
          },
          ['<Up>'] = {
            i = cmp.mapping.select_prev_item({ behavior = require('cmp.types').cmp.SelectBehavior.Select }),
          },
          ['<C-j>'] = cmp.mapping.select_next_item(),
          ['<C-k>'] = cmp.mapping.select_prev_item(),
          ['<C-d>'] = cmp.mapping.scroll_docs(4),
          ['<C-u>'] = cmp.mapping.scroll_docs(-4),
          ['<C-Space>'] = cmp.mapping.complete({}),
          ['<CR>'] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
          }),
        },
        sources = {
          { name = 'git' },
          {
            name = 'nvim_lsp',
            ---@param entry cmp.Entry
            ---@param _context cmp.Context
            entry_filter = function(entry, _context)
              -- Gets rid of noisy buffer word completion.
              return entry.completion_item.kind ~= require('cmp.types').lsp.CompletionItemKind.Text
            end,
          },
          { name = 'omni' },
          { name = 'luasnip' },
          { name = 'emoji' },
          { name = 'fish' },
          { name = 'async_path' },
          {
            name = 'lazydev',
            group_index = 0, -- set group index to 0 to skip loading LuaLS completions
          },
        },
      })
      cmp.setup.filetype('ghostty', {
        sources = {
          { name = 'omni' },
          { name = 'async_path' },
          { name = 'fonts', option = { space_filter = '-' } },
        },
      })
      cmp.setup.filetype('query', {
        sources = {
          { name = 'omni' },
        },
      })

      ---@param fallback function
      local function select_next_item(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        else
          fallback()
        end
      end
      ---@param fallback function
      local function select_prev_item(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        else
          fallback()
        end
      end
      ---@type cmp.ConfigSchema
      local search_config = {
        mapping = {
          ['<Down>'] = {
            c = select_next_item,
          },
          ['<Up>'] = {
            c = select_prev_item,
          },
          ['<C-j>'] = {
            c = select_next_item,
          },
          ['<C-k>'] = {
            c = select_prev_item,
          },
        },
        sources = {
          { name = 'buffer' },
        },
      }
      cmp.setup.cmdline('/', search_config)
      cmp.setup.cmdline('?', search_config)
      cmp.setup.cmdline(':', {
        mapping = search_config.mapping,
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
  },
}
