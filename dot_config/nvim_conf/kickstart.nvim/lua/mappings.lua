local nmap = require('utils.keymap').nmap

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
vim.keymap.set({ 'v', 'n' }, '<leader>Q', '<cmd>qa<cr>', { desc = 'Quit all' })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', 'g<Up>', { silent = true })
vim.keymap.set('n', 'j', 'g<Down>', { silent = true })
vim.keymap.set({ 'v', 'n' }, 'gj', '<C-i>', { desc = 'Go to next location' })
vim.keymap.set({ 'v', 'n' }, 'gk', '<C-o>', { desc = 'Go to previous location' })

nmap('Open LazyGit in buffer', 'gg', function()
  local bufnrs = vim.api.nvim_list_bufs()
  local lazygit_bufnr = vim.tbl_filter(function(bufnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    return bufname:match('term://.*lazygit')
  end, bufnrs)[1]
  if lazygit_bufnr ~= nil then
    vim.api.nvim_set_current_buf(lazygit_bufnr)
    return
  end
  vim.cmd('term lazygit')
end)
vim.api.nvim_create_autocmd('TermOpen', {
  pattern = 'term://*lazygit',
  callback = function(args)
    ---@type integer
    local bufnr = args.buf
    vim.cmd('startinsert')
    vim.api.nvim_buf_set_option(bufnr, 'number', false)
    vim.api.nvim_buf_set_option(bufnr, 'foldcolumn', '0')
    vim.api.nvim_buf_set_option(bufnr, 'statuscolumn', '')
  end,
})
vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    local current_bufnr = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_name(current_bufnr):match('term://.*lazygit') then
      vim.cmd('resize 0 0')
      vim.cmd('resize 100 100')
    end
  end,
})
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = 'term://*lazygit',
  callback = function()
    vim.cmd('startinsert')
  end,
})
vim.api.nvim_create_autocmd('TermClose', {
  pattern = 'term://*lazygit',
  callback = function(args)
    ---@type integer
    local bufnr = args.buf
    require('bufdelete').bufdelete(bufnr)
  end,
})
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*COMMIT_EDITMSG',
  callback = function(args)
    ---@type integer
    local commit_bufnr = args.buf
    vim.cmd('startinsert')
    local bufnrs = vim.api.nvim_list_bufs()
    local lazygit_bufnr = vim.tbl_filter(function(bufnr)
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      return bufname:match('term://.*lazygit')
    end, bufnrs)[1]
    if lazygit_bufnr ~= nil then
      vim.keymap.set('n', '<leader>q', function()
        require('bufdelete').bufdelete(commit_bufnr)
      end, { buffer = commit_bufnr })
    end
  end,
})

if not require('utils.config').USE_TABLINE then
  nmap('[C]lose current buffer', 'c', function()
    require('bufdelete').bufdelete()
  end)
end

-- Diagnostic keymaps
vim.keymap.set('n', '[d', function()
  vim.diagnostic.goto_prev()
end, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', function()
  vim.diagnostic.goto_next()
end, { desc = 'Go to next diagnostic message' })
nmap('Show hovered diagnostic', 'ds', function()
  vim.diagnostic.open_float()
end)

-- Remap <leader>+v to trigger visual block mode because pasting from clipboard is mapped to Ctrl-V
vim.keymap.set({ 'n', 'v' }, '<leader>v', '<C-v>', { desc = 'Visual block mode' })
-- System clipboard keymaps.
vim.keymap.set({ 'v', 'n' }, '<leader>y', '"+y', { desc = 'Yank selection to clipboard' })
vim.keymap.set({ 'v', 'n' }, '<leader>Y', '"+Y', { desc = 'Yank to end of line to clipboard' })
vim.keymap.set({ 'v', 'n' }, '<leader>p', '"+p', { desc = 'Paste from clipboard' })
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
    vim.schedule(function()
      vim.notify(notification_msg)
    end)
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

nmap('Load current[.] directory [s]ession', 'S.', function()
  require('session_manager').load_current_dir_session()
end)
nmap('[S]ave current directory [s]ession', 'Ss', function()
  require('session_manager').save_current_dir_session()
end)

nmap('[D]ismiss [n]otification', 'dn', function()
  require('notify').dismiss({ pending = true, silent = true })
end)
