local Table = require('utils.table')
local Config = require('utils.config')
local OSC = require('utils.osc')

-- Disable async parsing, many flickering issues
-- Re-enable when the following is closed: https://github.com/neovim/neovim/issues/32660
vim.g._ts_force_sync_parsing = true

-- [[ Setting options ]]
-- Folding setup for nvim-ufo
vim.o.foldcolumn = '1'
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.o.foldenable = true
vim.o.fillchars = 'eob: ,fold: ,foldopen:+,foldsep:│,foldclose:-'

vim.g.omni_sql_default_compl_type = 'syntax'

-- Default tab width of 2 spaces
vim.o.tabstop = 2

-- Don't show concealed text while in normal mode or when entering a command.
vim.o.concealcursor = 'nc'

function vim.brint(...)
  local output = {} --- @type string[]
  for i = 1, select('#', ...) do
    local o = select(i, ...)
    if type(o) == 'string' then
      output[#output + 1] = o
    elseif o == nil then
      output[#output + 1] = 'nil'
    else
      table.insert(output, vim.inspect(o, { newline = '\n', indent = '  ' }))
    end
  end
  -- Use a space to separate the arguments.
  print(table.concat(output, ' '))
end

---Workaround https://github.com/hrsh7th/cmp-omni/pull/10
---@diagnostic disable-next-line: duplicate-set-field
vim.treesitter.query.omnifunc = function(...)
  local ret = require('vim.treesitter._query_linter').omnifunc(...)
  if type(ret) ~= 'table' or type(ret.words) ~= 'table' then
    return ret
  end
  return Table.remove_duplicates(ret.words)
end

-- Fish startup can be slow, which results in things like lazygit and fzf-lua being slow
vim.o.shell = 'bash'

vim.o.showtabline = Config.USE_TABLINE and 2 or 0

--- Use tmux-aware OSC 52 for clipboard
--- @param clipboard string The clipboard to read from or write to
--- @param content string The Base64 encoded contents to write to the clipboard, or '?' to read
local function osc52(clipboard, content)
  return OSC.osc(string.format(']52;%s;%s', clipboard, content))
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

---@type function|table
local paste_command = paste_unsupported

if vim.env.TMUX ~= nil and vim.env.SSH_CONNECTION ~= nil then
  paste_command = paste_unsupported
elseif vim.fn.has('linux') == 1 then
  paste_command = { 'wl-paste' }
elseif vim.fn.has('mac') == 1 then
  paste_command = { 'pbpaste' }
else
  paste_command = paste_unsupported
end

vim.g.clipboard = {
  name = 'Tmux-Aware OSC 52',
  copy = {
    ['+'] = create_tmux_aware_copy_fn('+'),
    ['*'] = create_tmux_aware_copy_fn('*'),
  },
  paste = {
    ['+'] = paste_command,
    ['*'] = paste_command,
  },
}

---@type string[]
local current_sessionoptions = vim.opt.sessionoptions:get()
current_sessionoptions[#current_sessionoptions + 1] = 'globals'
current_sessionoptions = vim
  .iter(current_sessionoptions)
  :filter(function(opt)
    return opt ~= 'folds'
  end)
  :totable()
vim.opt.sessionoptions = current_sessionoptions
vim.api.nvim_set_hl(0, '@markup.link.label.markdown', { fg = '#2ac3de', underdotted = true, force = true })

local filetype_options_group = vim.api.nvim_create_augroup('FiletypeOptions', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'conf', 'sh', 'javascript' },
  group = filetype_options_group,
  callback = function()
    -- Remove prefixed '/' from includeexpr
    vim.bo.includeexpr = 'substitute(v:fname,"^\\s*/","","")'
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'diff' },
  group = filetype_options_group,
  callback = function()
    -- Remove `a/` or `b/` from includeexpr
    vim.bo.includeexpr = 'substitute(v:fname,"^[ab]/","","")'
  end,
})

-- Faster loading of nvim-ts-context-commentstring plugin
vim.g.skip_ts_context_commentstring_module = true

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'bazelrc',
  group = filetype_options_group,
  callback = function()
    vim.bo.commentstring = '# %s'
  end,
})

vim.filetype.add({
  extension = {
    mdx = 'markdown.mdx',
    swcrc = 'json',
    mdc = 'markdown',
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
  { name = 'DapBreakpoint', text = '', texthl = 'DapUILineNumber' },
  { name = 'DapBreakpointRejected', text = '', texthl = 'DiagnosticError' },
  { name = 'DapBreakpointCondition', text = '', texthl = 'DiagnosticInfo' },
  { name = 'DapLogPoint', text = '.>', texthl = 'DiagnosticInfo' },
}
for _, sign in ipairs(signs) do
  if not sign.texthl then
    sign.texthl = sign.name
  end
  if sign.name:match('^Dap') then
    vim.fn.sign_define(sign.name, sign)
  end
end

-- TODO: When the following issue is resolved, remove this hack: https://github.com/neovim/neovim/issues/19649
-- Adds relatedInformation to the diagnostic message
---@param diag vim.Diagnostic
local function format_diagnostic(diag)
  local message = diag.message
  ---@class lsp.DiagnosticInfo
  ---@field client_name? string
  ---@field relatedInformation? lsp.RelatedInformation[]
  local diag_lsp_info = diag and diag.user_data and diag.user_data.lsp or {}
  local client = vim.lsp.get_clients({ name = diag_lsp_info.client_name })[1]
  if not client then
    return diag.message
  end

  ---@class lsp.RelatedInformation
  ---@field message string
  ---@field location lsp.Location | lsp.LocationLink

  ---@type {messages: string[], locations: (lsp.Location | lsp.LocationLink)[]}
  local relatedInfo = { messages = {}, locations = {} }
  local lsp_related_info = diag_lsp_info.relatedInformation or {}
  for _, info in ipairs(lsp_related_info) do
    relatedInfo.messages[#relatedInfo.messages + 1] = info.message
    relatedInfo.locations[#relatedInfo.locations + 1] = info.location
  end

  for i, loc in ipairs(vim.lsp.util.locations_to_items(relatedInfo.locations, client.offset_encoding)) do
    message = string.format('%s\n\t%s (%s:%d)', message, relatedInfo.messages[i], vim.fn.fnamemodify(loc.filename, ':.'), loc.lnum)
  end

  return message
end
vim.diagnostic.config({
  virtual_text = true,
  signs = { active = signs },
  update_in_insert = true,
  underline = true,
  severity_sort = true,
  jump = {
    float = {
      format = format_diagnostic,
    },
  },
  float = {
    focused = false,
    style = 'minimal',
    border = 'rounded',
    source = true,
    header = '',
    prefix = '',
    format = format_diagnostic,
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
    -- Causes issues with fzf-lua
    if filetype == 'lazy' or filetype == 'fzf' then
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
    vim.hl.on_yank({ timeout = 150 })
  end,
  group = highlight_group,
  pattern = '*',
})
