-- [[ Setting options ]]
-- Folding setup for nvim-ufo
vim.o.foldcolumn = '1'
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true
vim.o.fillchars = 'eob: ,fold: ,foldopen:,foldsep:│,foldclose:'

function vim.brint(...)
  if vim.in_fast_event() then
    print(...)
    return
  end
  for i = 1, select('#', ...) do
    local o = select(i, ...)
    if type(o) == 'string' then
      vim.api.nvim_out_write(o)
    else
      vim.api.nvim_out_write(vim.inspect(o, { newline = '\n', indent = '  ' }))
    end
    -- Use a space to separate the arguments.
    vim.api.nvim_out_write(' ')
  end
  vim.api.nvim_out_write('\n')
end

-- Makes fish shell execution startup faster.
vim.env.FAST_PROMPT = '1'

vim.o.showtabline = require('utils.config').USE_TABLINE and 2 or 0

--- Use tmux-aware OSC 52 for clipboard
--- @param clipboard string The clipboard to read from or write to
--- @param content string The Base64 encoded contents to write to the clipboard, or '?' to read
local function osc52(clipboard, content)
  return require('utils.osc').osc(string.format(']52;%s;%s', clipboard, content))
end

---@param reg '+'|'*'
---@return fun(lines: string[]): nil
local function create_tmux_aware_copy_fn(reg)
  local clipboard = reg == '+' and 'c' or 'p'
  ---@param lines string[]
  return function(lines)
    local content = table.concat(lines, '\n')
    vim.api.nvim_chan_send(2, osc52(clipboard, vim.base64.encode(content)))
  end
end

local function paste_unsupported()
  vim.notify('OSC 52 clipboard paste unsupported, use ctrl-v', vim.log.levels.ERROR)
end

vim.g.clipboard = {
  name = 'Tmux-Aware OSC 52',
  copy = {
    ['+'] = create_tmux_aware_copy_fn('+'),
    ['*'] = create_tmux_aware_copy_fn('*'),
  },
  paste = {
    ['+'] = paste_unsupported,
    ['*'] = paste_unsupported,
  },
}

local current_sessionoptions = vim.opt.sessionoptions:get()
table.insert(current_sessionoptions, 'globals')
vim.opt.sessionoptions = current_sessionoptions
vim.api.nvim_set_hl(0, '@markup.link.label.markdown', { fg = '#2ac3de', underdotted = true, force = true })

-- Faster loading of nvim-ts-context-commentstring plugin
vim.g.skip_ts_context_commentstring_module = true

vim.filetype.add({
  filename = {
    -- Add chezmoi file name.
    ['dot_gitconfig'] = 'gitconfig',
  },
  extension = {
    mdx = 'markdown.mdx',
    swcrc = 'json',
  },
  pattern = {
    ['.*%.bazelrc'] = 'bazelrc',
    ['%.vscode/%w*%.json'] = 'jsonc',
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
