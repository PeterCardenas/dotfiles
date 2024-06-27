-- [[ Setting options ]]
-- Folding setup for nvim-ufo
vim.o.foldcolumn = '1'
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true
vim.o.fillchars = 'eob: ,fold: ,foldopen:,foldsep:│,foldclose:'

vim.o.showtabline = require('utils.config').USE_TABLINE and 2 or 0

local current_sessionoptions = vim.opt.sessionoptions:get()
table.insert(current_sessionoptions, 'globals')
vim.opt.sessionoptions = current_sessionoptions

-- Faster loading of nvim-ts-context-commentstring plugin
vim.g.skip_ts_context_commentstring_module = true

vim.filetype.add({
  filename = {
    ['.bazelrc'] = 'Bazelrc',
    -- Add chezmoi file name.
    ['dot_gitconfig'] = 'gitconfig',
  },
  extension = {
    mdx = 'markdown.mdx',
  },
})

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Enable true color support.
if vim.fn.has('termguicolors') == 1 then
  vim.o.termguicolors = true
end

-- Make global status work
vim.o.laststatus = 3

-- Highlight current text line of cursor
vim.o.cursorline = true
-- Number of lines to keep above and below the buffer
vim.o.scrolloff = 8

-- Make tabs default to 4 characters wide.
vim.o.tabstop = 4

-- Make line numbers default
vim.wo.number = true

-- Enable mouse mode
vim.o.mouse = 'a'
-- Enable tracking mouse movements.
vim.o.mousemoveevent = true

-- Enable camel case move_options
vim.g.camelcasemotion_key = '<leader>'

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt = 'menuone,noselect'

vim.o.shell = 'env FAST_PROMPT=1 /usr/bin/fish'

---@class SignDefinition: vim.fn.sign_define.dict
---@field name string

-- Style diagnostics
---@type SignDefinition[]
local signs = {
  { name = 'DiagnosticSignError', text = '' },
  { name = 'DiagnosticSignWarn', text = '' },
  { name = 'DiagnosticSignInfo', text = '' },
  { name = 'DiagnosticSignHint', text = '󰛩' },
  { name = 'DapStopped', text = '', texthl = 'DiagnosticWarn' },
  { name = 'DapBreakpoint', text = '', texthl = 'DiagnosticInfo' },
  { name = 'DapBreakpointRejected', text = '', texthl = 'DiagnosticError' },
  { name = 'DapBreakpointCondition', text = '', texthl = 'DiagnosticInfo' },
  { name = 'DapLogPoint', text = '.>', texthl = 'DiagnosticInfo' },
}
for _, sign in ipairs(signs) do
  if not sign.texthl then
    sign.texthl = sign.name
  end
  vim.fn.sign_define(sign.name, sign)
end
vim.diagnostic.config({
  virtual_text = true,
  signs = { active = signs },
  update_in_insert = true,
  underline = true,
  severity_sort = true,
  float = {
    focused = false,
    style = 'minimal',
    border = 'rounded',
    source = true,
    header = '',
    prefix = '',
  },
})

-- Set highlight based on whether searching is done.
vim.on_key(function(char)
  if vim.fn.mode() == 'n' then
    local new_hlsearch = vim.tbl_contains({ '<CR>', 'n', 'N', '*', '#', '?', '/' }, vim.fn.keytrans(char))
    if vim.o.hlsearch ~= new_hlsearch then
      vim.o.hlsearch = new_hlsearch
    end
  end
end, vim.api.nvim_create_namespace('auto_hlsearch'))

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})
