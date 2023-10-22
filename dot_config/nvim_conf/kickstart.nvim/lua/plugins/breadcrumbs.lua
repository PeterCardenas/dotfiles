-- local test = {
--   Boolean = ' ',
--   BreakStatement = '󰙧 ',
--   DoStatement = '󰑖 ',
--   Log = '󰦪 ',
--   Null = '󰢤 ',
--   Operator = '󰆕 ',
--   Pair = '󰅪 ',
-- }

---@type dropbar_configs_t
local DROPBAR_CONFIG = {
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
  general = {
    enable = function (buf, win)
      local default_enable = not vim.api.nvim_win_get_config(win).zindex
        and (vim.bo[buf].buftype == '' or vim.bo[buf].buftype == 'terminal')
        and vim.api.nvim_buf_get_name(buf) ~= ''
        and not vim.wo[win].diff
      local filetype = vim.bo[buf].filetype
      local disabled_filetypes = { 'python' }
      local is_filetype_enabled = not vim.tbl_contains(disabled_filetypes, filetype)
      return default_enable and is_filetype_enabled
    end
  }
}
vim.keymap.set({ 'n', 'v', 'i' }, '<C-f>',
  function()
    require('dropbar.api').pick()
  end,
  { desc = 'Focus on breadcrumbs' }
)
---@type LazyPluginSpec
return {
  'Bekaboo/dropbar.nvim',
  event = { 'BufReadPre', 'BufNewFile'},
  -- optional, but required for fuzzy finder support
  dependencies = {
    'nvim-telescope/telescope-fzf-native.nvim'
  },
  config = function()
    require('dropbar').setup(DROPBAR_CONFIG)
  end,
}
