local Lsp = require('utils.lsp')
local Treesitter = require('utils.treesitter')
local Table = require('utils.table')
local Config = require('utils.config')

---@type LazyPluginSpec[]
return {
  {
    -- Adds LSP completion capabilities
    'hrsh7th/cmp-nvim-lsp',
    ft = Lsp.FT_WITH_LSP,
    cond = function()
      return not Config.USE_BLINK_CMP
    end,
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
    'rcarriga/cmp-dap',
    ft = { 'dapui_watches', 'dapui_hover', 'dap-repl' },
  },
  {
    'saadparwaiz1/cmp_luasnip',
    cond = function()
      return not Config.USE_BLINK_CMP
    end,
    ft = Lsp.FT_WITH_LSP,
  },
  {
    -- Command completion
    'hrsh7th/cmp-cmdline',
    cond = function()
      return not Config.USE_BLINK_CMP
    end,
    event = { 'CmdlineEnter' },
  },
  {
    -- Get words from the current buffer
    'hrsh7th/cmp-buffer',
    cond = function()
      return not Config.USE_BLINK_CMP
    end,
    event = { 'CmdlineEnter' },
  },
  {
    -- Add completions for fish shell
    'mtoohey31/cmp-fish',
    ft = { 'fish' },
  },
  {
    -- Git/GitHub completion
    'PeterCardenas/cmp-git',
    branch = 'working-state',
    event = { 'InsertEnter' },
    config = function()
      local ssh_aliases = {
        ['personal-github.com'] = 'github.com',
        ['work-github.com'] = 'github.com',
      }
      require('cmp_git').setup({
        -- Enable completion for all filetypes to get them in comments.
        filetypes = { '*' },
        ssh_aliases = ssh_aliases,
        github = {
          issues = {
            filter = 'assigned',
            limit = 100,
          },
          mentions = {
            limit = math.huge,
            prefetch = true,
            fetch_teams = true,
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
            resolve = function(sources, item, callback, git_info)
              return sources.github:resolve_mention(item, callback, git_info)
            end,
          },
        },
      })
    end,
  },
  {
    -- Emoji completion
    'hrsh7th/cmp-emoji',
    event = { 'InsertEnter' },
  },
  {
    -- Autocompletion
    'hrsh7th/nvim-cmp',
    dependencies = {
      -- omnifunc completion
      'hrsh7th/cmp-omni',

      -- File path completion
      'https://codeberg.org/FelipeLema/cmp-async-path',
    },
    event = { 'InsertEnter', 'CmdlineEnter' },
    cond = function()
      return not Config.USE_BLINK_CMP
    end,
    config = function()
      local cmp = require('cmp')
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
            behavior = require('cmp.types').cmp.ConfirmBehavior.Replace,
            select = true,
          }),
        },
        sources = {
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
          { name = 'fish' },
          { name = 'async_path' },
          { name = 'emoji' },
          { name = 'git' },
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
      cmp.setup.filetype({ 'dap-repl', 'dapui_watches', 'dapui_hover' }, {
        enabled = function()
          return vim.bo.filetype ~= 'prompt' or require('cmp_dap').is_dap_buffer()
        end,
        sources = {
          { name = 'dap' },
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
          ['<C-n>'] = nil,
          ['<C-p>'] = nil,
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
  {
    'moyiz/blink-emoji.nvim',
    lazy = true,
  },
  {
    'saghen/blink.compat',
    lazy = true,
    config = function()
      require('blink.compat').setup({
        impersonate_nvim_cmp = true,
      })
    end,
  },
  {
    'saghen/blink.cmp',
    version = '*',
    event = { 'InsertEnter', 'CmdlineEnter' },
    -- TODO: Allow building from main with build = 'cargo build --release'
    -- Currently it's trying to build for arm when neovim is currently built with x86_64
    cond = function()
      return Config.USE_BLINK_CMP
    end,
    config = function()
      local function maybe_get_dap()
        local is_enabled = vim.bo.filetype ~= 'prompt' or require('cmp_dap').is_dap_buffer()
        if is_enabled then
          return { 'dap' }
        end
        return {}
      end
      require('blink.cmp').setup({
        keymap = {
          preset = 'none',
          ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
          ['<C-j>'] = { 'select_next', 'fallback' },
          ['<C-k>'] = { 'select_prev', 'fallback' },
          ['<C-u>'] = { 'scroll_documentation_up', 'fallback' },
          ['<C-d>'] = { 'scroll_documentation_down', 'fallback' },
          ['<C-s>'] = { 'show_signature', 'hide_signature', 'fallback' },
          ['<CR>'] = { 'accept', 'fallback' },
        },
        fuzzy = {
          implementation = 'prefer_rust',
          prebuilt_binaries = {
            download = true,
            force_version = 'v1.0.0',
            ignore_version_mismatch = true,
          },
        },
        snippets = {
          preset = 'luasnip',
        },
        appearance = {
          kind_icons = {
            Commit = '',
            Mention = '',
            PR = '',
            MR = '',
            Issue = '',
            Text = '󰉿',
            Method = '󰆧',
            Function = '󰊕',
            Constructor = '',
            Field = '󰜢',
            Variable = '󰀫',
            Class = '󰠱',
            Interface = '',
            Module = '',
            Property = '󰜢',
            Unit = '󰑭',
            Value = '󰎠',
            Enum = '',
            Keyword = '󰌋',
            Snippet = '',
            Color = '󰏘',
            File = '󰈙',
            Reference = '󰈇',
            Folder = '󰉋',
            EnumMember = '',
            Constant = '󰏿',
            Struct = '󰙅',
            Event = '',
            Operator = '󰆕',
          },
        },
        sources = {
          default = function()
            local sources = { 'omni', 'lazydev', 'lsp', 'path', 'snippets' }
            local ft = vim.bo.filetype
            if ft == 'markdown' or Treesitter.inside_comment_block() then
              sources[#sources + 1] = 'emoji'
              sources[#sources + 1] = 'git'
            elseif Treesitter.inside_string() then
              sources[#sources + 1] = 'emoji'
            end
            if ft == 'fish' then
              sources[#sources + 1] = 'fish'
            end
            return sources
          end,
          per_filetype = {
            octo = { 'emoji', 'git', 'path' },
            gitcommit = { 'git', 'emoji', 'path' },
            ghostty = { 'omni', 'path', 'fonts', 'emoji' },
            query = { 'omni' },
            ['dap-repl'] = maybe_get_dap,
            ['dapui_watches'] = maybe_get_dap,
            ['dapui_hover'] = maybe_get_dap,
            -- TODO: Adding the following makes loading the sidebar really slow
            -- AvanteInput = { 'avante_commands', 'avante_mentions', 'avante_files' },
          },
          providers = {
            avante_commands = {
              name = 'avante_commands',
              module = 'blink.compat.source',
            },
            avante_files = {
              name = 'avante_files',
              module = 'blink.compat.source',
            },
            avante_mentions = {
              name = 'avante_mentions',
              module = 'blink.compat.source',
            },
            fonts = {
              name = 'fonts',
              module = 'blink.compat.source',
            },
            lazydev = {
              name = 'LazyDev',
              module = 'lazydev.integrations.blink',
              score_offset = 100,
            },
            fish = {
              name = 'fish',
              module = 'blink.compat.source',
            },
            emoji = {
              -- TODO: Use blink-emoji.nvim, once it loads completions faster, since it has more emojis.
              module = 'blink.compat.source',
              name = 'emoji',
              -- Force icon to be text instead of field
              transform_items = function(_ctx, items)
                local kind = require('blink.cmp.types').CompletionItemKind.Text
                for i = 1, #items do
                  items[i].kind = kind
                end
                return items
              end,
            },
            dap = {
              module = 'blink.compat.source',
              name = 'dap',
            },
            git = {
              name = 'git',
              module = 'blink.compat.source',
              async = true,
              transform_items = function(_ctx, items)
                for _, item in ipairs(items) do
                  if vim.startswith(item.label, '#') then
                    item.kind_name = 'Issue'
                  end
                  if vim.startswith(item.label, '@') then
                    item.kind_name = 'Mention'
                  end
                end
                -- TODO: cmp-git somehow is adding duplicates.
                local new_items = Table.remove_duplicates(items, function(item)
                  return item.label
                end)
                return new_items
              end,
            },
            omni = {
              enabled = function()
                return vim.bo.omnifunc ~= 'v:lua.vim.lsp.omnifunc' and vim.bo.omnifunc ~= 'v:lua.octo_omnifunc'
              end,
            },
          },
        },
        completion = {
          menu = {
            draw = {
              components = {
                kind_icon = {
                  text = function(ctx)
                    local icon = ctx.kind_icon
                    if 'Path' == ctx.source_name then
                      ---@type string?, string
                      local dev_icon, _dev_hl = require('nvim-web-devicons').get_icon(ctx.label)
                      if dev_icon then
                        icon = dev_icon
                      end
                    end

                    return icon .. ctx.icon_gap
                  end,
                  highlight = function(ctx)
                    local hl = ctx.kind_hl
                    if 'Path' == ctx.source_name then
                      ---@type string?, string
                      local dev_icon, dev_hl = require('nvim-web-devicons').get_icon(ctx.label)
                      if dev_icon then
                        hl = dev_hl
                      end
                    end
                    return hl
                  end,
                },
              },
            },
          },
          documentation = {
            auto_show = true,
            auto_show_delay_ms = 100,
            update_delay_ms = 100,
            window = {
              direction_priority = {
                menu_south = { 'e', 'w', 'n', 's' },
              },
            },
          },
        },
        cmdline = {
          keymap = {
            preset = 'none',
            ['<C-j>'] = { 'select_next', 'fallback' },
            ['<C-k>'] = { 'select_prev', 'fallback' },
            ['<C-u>'] = { 'scroll_documentation_up', 'fallback' },
            ['<C-d>'] = { 'scroll_documentation_down', 'fallback' },
            ['<CR>'] = { 'accept_and_enter', 'fallback' },
            ['<C-Y>'] = { 'accept', 'fallback' },
          },
          completion = {
            list = {
              selection = {
                preselect = false,
              },
            },
            menu = {
              auto_show = true,
            },
          },
        },
      })
    end,
  },
}
