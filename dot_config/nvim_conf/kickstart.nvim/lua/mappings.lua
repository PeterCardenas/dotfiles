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

vim.keymap.set('n', '|', function()
  vim.cmd('vs')
end, { desc = 'Vertical split' })

-- Shift-J/K to move lines up and down.
vim.keymap.set('v', '<S-j>', ":m '>+1<CR>gv=gv", { desc = 'Move line down', noremap = true, silent = true })
vim.keymap.set('v', '<S-k>', ":m '<-2<CR>gv=gv", { desc = 'Move line up', noremap = true, silent = true })

vim.keymap.set({ 'v', 'n' }, '<leader>s', '<cmd>w<cr>', { desc = 'Save file' })
vim.keymap.set({ 'v', 'n' }, '<leader>q', '<cmd>q<cr>', { desc = 'Quit split' })
vim.keymap.set({ 'v', 'n' }, '<leader>Q', '<cmd>qa<cr>', { desc = 'Quit all' })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', 'g<Up>', { silent = true })
vim.keymap.set('n', 'j', 'g<Down>', { silent = true })
vim.keymap.set({ 'v', 'n' }, 'gj', '<C-i>', { desc = 'Go to next location' })
vim.keymap.set({ 'v', 'n' }, 'gk', '<C-o>', { desc = 'Go to previous location' })

vim.keymap.set('n', '<leader>o', function()
  require('nvim-tree.actions').tree.toggle.fn({ find_file = true })
end, { desc = 'Toggle file explorer' })
vim.keymap.set('n', '<leader>gg', function()
  require('lazygit').lazygit()
end, { desc = 'Open Floating LazyGit' })

-- Diagnostic keymaps
vim.keymap.set('n', '[d', function()
  vim.diagnostic.goto_prev()
end, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', function()
  vim.diagnostic.goto_next()
end, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>ds', function()
  vim.diagnostic.open_float()
end, { desc = 'Show hovered diagnostic' })

-- Remap <leader>+v to trigger visual block mode because pasting from clipboard is mapped to Ctrl-V
vim.keymap.set({ 'n', 'v' }, '<leader>v', '<C-v>', { desc = 'Visual block mode' })
-- System clipboard keymaps.
vim.keymap.set({ 'v', 'n' }, '<leader>y', '"+y', { desc = 'Yank selection to clipboard' })
vim.keymap.set({ 'v', 'n' }, '<leader>Y', '"+Y', { desc = 'Yank to end of line to clipboard' })
vim.keymap.set({ 'v', 'n' }, '<leader>p', '"+p', { desc = 'Paste from clipboard' })
vim.keymap.set({ 'v', 'n', 'i' }, '<C-v>', '"+p', { desc = 'Paste from clipboard' })

-- Set spaces per indent
local function set_indent()
  local input_avail, input = pcall(vim.fn.input, 'Set indent value (>0 expandtab, <=0 noexpandtab): ')
  if input_avail then
    local indent = tonumber(input)
    if not indent or indent == 0 then
      return
    end
    vim.bo.expandtab = (indent > 0) -- local to buffer
    indent = math.abs(indent)
    vim.bo.tabstop = indent -- local to buffer
    vim.bo.softtabstop = indent -- local to buffer
    vim.bo.shiftwidth = indent -- local to buffer
    local notification_msg = string.format('indent=%d %s', indent, vim.bo.expandtab and 'expandtab' or 'noexpandtab')
    vim.schedule(function()
      vim.notify(notification_msg)
    end)
  end
end
vim.keymap.set({ 'n', 'v' }, '<leader>ui', function()
  set_indent()
end, { desc = 'Change indent setting' })
vim.keymap.set({ 'n' }, '<leader>ud', function()
  if vim.diagnostic.is_disabled(0) then
    vim.diagnostic.enable(0)
  else
    vim.diagnostic.disable(0)
  end
end, { desc = 'Toggle diagnostics' })

vim.keymap.set('n', '<leader>S.', function()
  require('session_manager').load_current_dir_session()
end, { desc = 'Load current directory session' })
vim.keymap.set('n', '<leader>Ss', function()
  require('session_manager').save_current_dir_session()
end, { desc = 'Save current directory session' })

vim.keymap.set('n', '<leader>dn', function()
  require('notify').dismiss({ pending = true, silent = true })
end, { desc = '[D]ismiss [n]otification' })
