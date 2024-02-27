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

-- Manage Buffers
vim.keymap.set({ 'v', 'n' }, '<leader>C', function()
  local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
  require('bufdelete').bufdelete(bufs, true)
end, { desc = 'Close all buffers' })
---@param navigation_offset integer
local function nav_buf(navigation_offset)
  local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
  local current_bufnr = vim.api.nvim_get_current_buf()
  for i, bufnr in ipairs(bufs) do
    if bufnr == current_bufnr then
      local new_bufnr_idx = (i + navigation_offset - 1) % #bufs + 1
      vim.cmd.b(bufs[new_bufnr_idx])
      break
    end
  end
end
---@param bufnr integer
local function force_close_buf(bufnr)
  vim.schedule(function()
    require('bufdelete').bufdelete(bufnr, true)
  end)
end
local function close_buf()
  local current_bufnr = vim.api.nvim_get_current_buf()
  local is_modified = vim.api.nvim_get_option_value('modified', { buf = current_bufnr })
  if is_modified then
    local choice = vim.fn.input('Buffer modified. Save? (y/n): ')
    if choice == 'y' then
      vim.cmd.w()
    elseif choice ~= 'n' then
      vim.notify('Buffer close failed.', vim.log.levels.WARN)
      return
    end
  end
  local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
  if #bufs == 1 then
    force_close_buf(current_bufnr)
    return
  end
  local jumplist_result = vim.fn.getjumplist()
  if not jumplist_result then
    force_close_buf(current_bufnr)
    return
  end
  local jumplist, current_jumplist_index = jumplist_result[1], jumplist_result[2]
  local target_jumplist_index = current_jumplist_index
  local target_bufnr = jumplist[target_jumplist_index].bufnr
  while target_jumplist_index > 1 and (current_bufnr == target_bufnr or not vim.tbl_contains(bufs, target_bufnr)) do
    target_jumplist_index = target_jumplist_index - 1
    target_bufnr = jumplist[target_jumplist_index].bufnr
  end
  vim.cmd.b(target_bufnr)
  force_close_buf(current_bufnr)
end
---@param move_offset integer
local function move_buf(move_offset)
  if move_offset == 0 then
    return
  end -- if n = 0 then no shifts are needed
  local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
  for i, bufnr in ipairs(bufs) do -- loop to find current buffer
    if bufnr == vim.api.nvim_get_current_buf() then -- found index of current buffer
      for _ = 0, (move_offset % #bufs) - 1 do -- calculate number of right shifts
        local new_i = i + 1 -- get next i
        if i == #bufs then -- if at end, cycle to beginning
          new_i = 1 -- next i is actually 1 if at the end
          local val = bufs[i] -- save value
          table.remove(bufs, i) -- remove from end
          table.insert(bufs, new_i, val) -- insert at beginning
        else -- if not at the end,then just do an in place swap
          bufs[i], bufs[new_i] = bufs[new_i], bufs[i]
        end
        i = new_i -- iterate i to next value
      end
      break
    end
  end
  -- set buffers
  vim.api.nvim_tabpage_set_var(0, 'bufs', bufs)
  -- redraw tabline
  vim.cmd.redrawtabline()
end
vim.keymap.set('n', '<leader>c', close_buf, { desc = 'Close buffer' })
vim.keymap.set('n', '<S-l>', function()
  local navigation_offset = vim.v.count > 0 and vim.v.count or 1
  nav_buf(navigation_offset)
end, { desc = 'Next buffer' })
vim.keymap.set('n', '<S-h>', function()
  local navigation_offset = -(vim.v.count > 0 and vim.v.count or 1)
  nav_buf(navigation_offset)
end, { desc = 'Previous buffer' })
vim.keymap.set('n', '<leader>rl', function()
  move_buf(vim.v.count > 0 and vim.v.count or 1)
end, { desc = 'Move buffer tab right' })
vim.keymap.set('n', '<leader>rh', function()
  move_buf(-(vim.v.count > 0 and vim.v.count or 1))
end, { desc = 'Move buffer tab left' })

vim.keymap.set('n', '<leader>S.', function()
  require('session_manager').load_current_dir_session()
end, { desc = 'Load current directory session' })
vim.keymap.set('n', '<leader>Ss', function()
  require('session_manager').save_current_dir_session()
end, { desc = 'Save current directory session' })

vim.keymap.set('n', '<leader>dn', function()
  require('notify').dismiss({ pending = true, silent = true })
end, { desc = '[D]ismiss [n]otification' })
