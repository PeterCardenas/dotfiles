-- [[ Setting options ]]
-- Folding setup for nvim-ufo
vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldenable = true
vim.opt.fillchars = 'eob: ,fold: ,foldopen:,foldsep:│,foldclose:'

-- Enable true color support.
if vim.fn.has('termguicolors') == 1 then
  vim.opt.termguicolors = true
end

-- Make global status work
vim.opt.laststatus = 3

-- Highlight current text line of cursor
vim.opt.cursorline = true
-- Number of lines to keep above and below the buffer
vim.opt.scrolloff = 8

-- Make line numbers default
vim.wo.number = true

-- Enable mouse mode
vim.o.mouse = 'a'

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

-- Style diagnostics
local signs = {
  { name = "DiagnosticSignError", text = "" },
  { name = "DiagnosticSignWarn", text = "" },
  { name = "DiagnosticSignHint", text = "" },
  { name = "DiagnosticSignInfo", text = "" },
  { name = "DiagnosticSignError", text = "" },
  { name = "DapStopped", text = "", texthl = "DiagnosticWarn" },
  { name = "DapBreakpoint", text = "", texthl = "DiagnosticInfo" },
  { name = "DapBreakpointRejected", text = "", texthl = "DiagnosticError" },
  { name = "DapBreakpointCondition", text = "", texthl = "DiagnosticInfo" },
  { name = "DapLogPoint", text = ".>", texthl = "DiagnosticInfo" },
}
for _, sign in ipairs(signs) do
  if not sign.texthl then sign.texthl = sign.name end
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
    style = "minimal",
    border = "rounded",
    source = "always",
    header = "",
    prefix = "",
  },
})

-- Set highlight based on whether searching is done.
vim.on_key(function(char)
  if vim.fn.mode() == "n" then
    local new_hlsearch = vim.tbl_contains({ "<CR>", "n", "N", "*", "#", "?", "/" }, vim.fn.keytrans(char))
    if vim.opt.hlsearch:get() ~= new_hlsearch then vim.opt.hlsearch = new_hlsearch end
  end
end, vim.api.nvim_create_namespace "auto_hlsearch")

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
