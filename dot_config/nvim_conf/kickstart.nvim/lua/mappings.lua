local nmap = require('utils.keymap').nmap
local Config = require('utils.config')
local Buf = require('utils.buf')
local Lazygit = require('local.lazygit')
local Log = require('utils.log')

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Space now does nothing
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })
-- Stay in indent mode
vim.keymap.set('v', '<', '<gv', { desc = 'unindent line' })
vim.keymap.set('v', '>', '>gv', { desc = 'indent line' })

vim.keymap.set({ 'n', 'v', 'i' }, '<C-g>', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(bufname, ':~:.')
  vim.fn.setreg('+', relative_path)
  vim.notify('Copied relative path to clipboard:\n' .. relative_path)
end)

vim.keymap.set('n', '|', function()
  vim.cmd('vs')
end, { desc = 'Vertical split' })

-- Shift-J/K to move lines up and down.
vim.keymap.set('x', '<S-j>', ":m '>+1<CR>gv=gv", { desc = 'Move line down', noremap = true, silent = true })
vim.keymap.set('x', '<S-k>', ":m '<-2<CR>gv=gv", { desc = 'Move line up', noremap = true, silent = true })

local function save_file()
  if vim.bo.readonly then
    vim.cmd('SudaWrite')
    vim.cmd('e')
  else
    vim.cmd('w')
  end
end
vim.keymap.set({ 'v', 'n' }, '<leader>s', save_file, { desc = 'Save file' })
vim.keymap.set({ 'v', 'n' }, '<leader>q', '<cmd>q<cr>', { desc = 'Quit split' })
vim.keymap.set({ 'v', 'n' }, '<leader>Q', function()
  ---@type string[]
  local modified_buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
      local bufname = vim.api.nvim_buf_get_name(buf)
      modified_buffers[#modified_buffers + 1] = bufname == '' and '[No Name]' or bufname
    end
  end

  if #modified_buffers > 0 then
    local msg = 'Cannot quit. Modified buffers:\n' .. table.concat(modified_buffers, '\n')
    Log.notify_error(msg)
  else
    vim.cmd('qa')
  end
end, { desc = 'Quit all' })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', 'g<Up>', { silent = true })
vim.keymap.set('n', 'j', 'g<Down>', { silent = true })
vim.keymap.set({ 'v', 'n' }, 'gj', '<C-i>', { desc = 'Go to next location' })
vim.keymap.set({ 'v', 'n' }, 'gk', '<C-o>', { desc = 'Go to previous location' })

Lazygit.set_keymap()

if not Config.USE_TABLINE then
  vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
    group = vim.api.nvim_create_augroup('close_current_buffer', { clear = true }),
    callback = function(args)
      local bufname = vim.api.nvim_buf_get_name(args.buf)
      if vim.startswith(bufname, 'octo:/') then
        return
      end
      vim.keymap.set('n', '<leader>c', Buf.close_current_buffer, { buffer = args.buf, desc = 'Close buffer' })
    end,
  })
end

---@param direction 'next'|'prev'
local function jump_to_diagnostic(direction)
  local count = direction == 'next' and 1 or -1
  local Format = require('plugins.lsp.format')
  local seen_namespace_count = 0
  local diagnostic ---@type vim.Diagnostic?
  local success = false
  repeat
    success, diagnostic = pcall(vim.diagnostic.jump, { count = count })
    if not success then
      break
    end
    seen_namespace_count = seen_namespace_count + (diagnostic and diagnostic.namespace == Format.format_diagnostic_namespace and 1 or 0)
  until not diagnostic or diagnostic.namespace ~= Format.format_diagnostic_namespace or seen_namespace_count > 1
end

-- Diagnostic keymaps
vim.keymap.set('n', '[d', function()
  jump_to_diagnostic('prev')
end, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', function()
  jump_to_diagnostic('next')
end, { desc = 'Go to next diagnostic message' })
nmap('Show hovered diagnostic', 'lh', function()
  vim.diagnostic.open_float({ scope = 'cursor' })
end)

-- Remap <leader>+v to trigger visual block mode because pasting from clipboard is mapped to Ctrl-V
vim.keymap.set({ 'n', 'v' }, '<leader>v', '<C-v>', { desc = 'Visual block mode' })
-- System clipboard keymaps.
vim.keymap.set({ 'v', 'n' }, '<leader>y', '"+y', { desc = 'Yank selection to clipboard' })
vim.keymap.set({ 'v', 'n' }, '<leader>Y', '"+Y', { desc = 'Yank to end of line to clipboard' })
vim.keymap.set({ 'v', 'n', 'i' }, '<C-v>', '"+p', { desc = 'Paste from clipboard' })

---Set spaces per indent
---@param indent number
local function set_indent(indent)
  vim.bo.expandtab = (indent > 0) -- local to buffer
  indent = math.abs(indent)
  vim.bo.tabstop = indent -- local to buffer
  vim.bo.softtabstop = indent -- local to buffer
  vim.bo.shiftwidth = indent -- local to buffer
end
local function request_and_set_indent()
  local input_avail, input = pcall(vim.fn.input, 'Set indent value (>0 expandtab, <=0 noexpandtab): ')
  if input_avail then
    local indent = tonumber(input)
    if not indent or indent == 0 then
      return
    end
    set_indent(indent)
    local notification_msg = string.format('indent=%d %s', indent, vim.bo.expandtab and 'expandtab' or 'noexpandtab')
    Log.notify_info(notification_msg)
  end
end
vim.keymap.set({ 'n', 'v' }, '<leader>ui', function()
  request_and_set_indent()
end, { desc = 'Change indent setting' })
nmap('Toggle diagnostics', 'ud', function()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local is_enabled_for_buf = vim.diagnostic.is_enabled({ bufnr = current_bufnr })
  vim.diagnostic.enable(not is_enabled_for_buf, { bufnr = current_bufnr })
end)
local is_showing_statusline = true
nmap('Toggle status line', 'ul', function()
  is_showing_statusline = not is_showing_statusline
  require('lualine').hide({ unhide = is_showing_statusline, place = { 'statusline' } })
end)
nmap('Toggle conceal level', 'uc', function()
  ---@type 0|1|2
  local cur_level = vim.opt_local.conceallevel:get()
  local new_level = cur_level == 0 and 2 or 0
  vim.opt_local.conceallevel:remove(cur_level)
  vim.opt_local.conceallevel:append(new_level)
end)
nmap('Toggle whitespace in diff', 'uw', function()
  ---@type string[]
  local diffopt = vim.opt_local.diffopt:get()
  local has_whitespace = vim.tbl_contains(diffopt, 'iwhiteall')
  if has_whitespace then
    vim.opt_local.diffopt:remove('iwhiteall')
  else
    vim.opt_local.diffopt:append('iwhiteall')
  end
end)
nmap('Toggle line wrap', 'ur', function()
  vim.o.wrap = not vim.o.wrap
end)

nmap('Load current[.] directory [s]ession', 'S.', function()
  require('session_manager').load_current_dir_session()
end)
nmap('[S]ave current directory [s]ession', 'Ss', function()
  require('session_manager').save_current_dir_session()
end)

nmap('[D]ismiss [n]otification', 'dn', function()
  require('notify').dismiss({ pending = true, silent = true })
end)
