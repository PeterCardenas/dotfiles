-- [[ Setting options ]]
-- Folding setup for nvim-ufo
vim.o.foldcolumn = '1'
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true
vim.o.fillchars = 'eob: ,fold: ,foldopen:+,foldsep:│,foldclose:-'

-- Default tab width of 2 spaces
vim.o.tabstop = 2

-- Don't show concealed text while in normal mode or when entering a command.
vim.o.concealcursor = 'nc'

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

---Workaround https://github.com/hrsh7th/cmp-omni/pull/10
---@diagnostic disable-next-line: duplicate-set-field
vim.treesitter.query.omnifunc = function(...)
  local ret = require('vim.treesitter._query_linter').omnifunc(...)
  if type(ret) ~= 'table' or type(ret.words) ~= 'table' then
    return ret
  end
  return require('utils.table').remove_duplicates(ret.words)
end

-- Fish startup can be slow, which results in things like lazygit and fzf-lua being slow
vim.o.shell = 'bash'

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
current_sessionoptions = vim
  .iter(current_sessionoptions)
  :filter(function(opt)
    return opt ~= 'folds'
  end)
  :totable()
vim.opt.sessionoptions = current_sessionoptions
vim.api.nvim_set_hl(0, '@markup.link.label.markdown', { fg = '#2ac3de', underdotted = true, force = true })

-- Faster loading of nvim-ts-context-commentstring plugin
vim.g.skip_ts_context_commentstring_module = true

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'bazelrc',
  callback = function()
    vim.bo.commentstring = '# %s'
  end,
})

vim.filetype.add({
  extension = {
    mdx = 'markdown.mdx',
    swcrc = 'json',
    swiftinterface = 'swift',
    -- Source: https://github.com/gpanders/dotfiles/blob/master/.config/nvim/filetype.lua
    h = function(path)
      -- Try to be a little intelligent when determining if a .h file is C++ or C

      -- If a .cc or .cpp file with the same basename exists next to this
      -- header file, assume the header is C++
      local stem = vim.fn.fnamemodify(path, ':r')
      if vim.uv.fs_stat(string.format('%s.cc', stem)) or vim.uv.fs_stat(string.format('%s.cpp', stem)) then
        return 'cpp'
      end

      -- If the header file contains C++ specific keywords, assume it is
      -- C++
      if
        vim.fn.search(
          string.format(
            [[\C\%%(%s\)]],
            table.concat({
              [[^#include <[^>.]\+>$]],
              [[\<constexpr\>]],
              [[\<consteval\>]],
              [[\<extern "C"\>]],
              [[^class\> [A-Z]],
              [[^\s*using\>]],
              [[\<template\>\s*<]],
              [[\<std::]],
            }, '\\|')
          ),
          'nw'
        ) ~= 0
      then
        return 'cpp'
      end

      return 'c'
    end,
  },
  pattern = {
    ['.*%.bazelrc'] = 'bazelrc',
    ['%.vscode/%w*%.json'] = 'jsonc',
    ['.*/git/ignore'] = 'gitignore',
    ['.*/git/config'] = 'gitconfig',
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

-- Go into insert mode when opening a terminal
vim.api.nvim_create_autocmd('TermOpen', {
  callback = function(opts)
    ---@type integer
    local bufnr = opts.buf
    vim.cmd('startinsert')
    vim.api.nvim_buf_set_option(bufnr, 'number', false)
    vim.api.nvim_buf_set_option(bufnr, 'foldcolumn', '0')
    vim.api.nvim_buf_set_option(bufnr, 'statuscolumn', '')
  end,
})
-- Close the terminal buffer when job finishes.
vim.api.nvim_create_autocmd('TermClose', {
  callback = function(args)
    ---@type integer
    local bufnr = args.buf
    local filetype = vim.bo[bufnr].filetype
    -- Closing lazy terminal buffers is handled by lazy.nvim
    if filetype == 'lazy' then
      return
    end
    require('bufdelete').bufdelete(bufnr)
  end,
})

-- Expand ghostty filetype for filename prefixed with "config"
vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
  pattern = '*/ghostty/config*',
  callback = function(args)
    ---@type number
    local buf = args.buf
    vim.api.nvim_set_option_value('filetype', 'ghostty', { buf = buf })
  end,
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
