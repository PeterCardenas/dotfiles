-- local test = {
--   Boolean = ' ',
--   BreakStatement = '󰙧 ',
--   DoStatement = '󰑖 ',
--   Log = '󰦪 ',
--   Null = '󰢤 ',
--   Operator = '󰆕 ',
--   Pair = '󰅪 ',
-- }

vim.keymap.set({ 'n', 'v', 'i' }, '<C-f>',
  function()
    require('dropbar.api').pick()
  end,
  { desc = 'Focus on breadcrumbs' }
)
---@type LazyPluginSpec
return {
  'Bekaboo/dropbar.nvim',
  -- optional, but required for fuzzy finder support
  dependencies = {
    'nvim-telescope/telescope-fzf-native.nvim'
  },
  config = function()
    require('dropbar').setup({
      icons = {
        kinds = {
          symbols = {
            Array             = ' ',
            Call              = ' ',
            CaseStatement     = ' ',
            Class             = 'פּ ',
            Color             = ' ',
            Constant          = ' ',
            Constructor       = ' ',
            ContinueStatement = '→ ',
            Copilot           = ' ',
            Declaration       = ' ',
            Delete            = ' ',
            Enum              = ' ',
            EnumMember        = ' ',
            Event             = ' ',
            Field             = ' ',
            File              = ' ',
            Folder            = ' ',
            ForStatement      = ' ',
            Function          = ' ',
            H1Marker          = ' ', -- Used by markdown treesitter parser
            H2Marker          = ' ',
            H3Marker          = ' ',
            H4Marker          = ' ',
            H5Marker          = ' ',
            H6Marker          = ' ',
            Identifier        = ' ',
            IfStatement       = ' ',
            Interface         = ' ',
            Keyword           = ' ',
            List              = ' ',
            Lsp               = ' ',
            Macro             = ' ',
            MarkdownH1        = ' ', -- Used by builtin markdown source
            MarkdownH2        = ' ',
            MarkdownH3        = ' ',
            MarkdownH4        = ' ',
            MarkdownH5        = ' ',
            MarkdownH6        = ' ',
            Method            = ' ',
            Module            = ' ',
            Namespace         = ' ',
            Number            = ' ',
            Object            = ' ',
            Package           = ' ',
            Property          = ' ',
            Reference         = ' ',
            Regex             = ' ',
            Repeat            = ' ',
            Scope             = ' ',
            Snippet           = ' ',
            Specifier         = ' ',
            Statement         = ' ',
            String            = " ",
            Struct            = ' ',
            SwitchStatement   = ' ',
            Text              = " ",
            Type              = ' ',
            TypeParameter     = ' ',
            Unit              = ' ',
            Value             = ' ',
            Variable          = ' ',
            WhileStatement    = ' ',
          }
        },
        ui = {
          bar = {
            separator = '> ',
          },
          menu = {
            indicator = '> ',
          },
        }
      },
    })
  end,
}
