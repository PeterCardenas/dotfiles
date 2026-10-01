vim.opt.rtp:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.system({ 'git', '-C', root, 'init', '-q' })
local filename = root .. '/visible.txt'
vim.fn.writefile({ 'KEEP_ME', 'another line' }, filename)
vim.fn.system({ 'git', '-C', root, 'add', 'visible.txt' })
vim.fn.system({ 'git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'initial' })
vim.fn.writefile({ 'KEEP_ME', 'another line', 'changed' }, filename)
vim.cmd.cd(vim.fn.fnameescape(root))

package.loaded['utils.file'] = {
  get_git_root = function()
    return root
  end,
}
local timer_callback
local timer_stopped = false
package.loaded['utils.spinner'] = {
  create_timer = function()
    return {
      start = function(callback)
        timer_callback = callback
      end,
      stop = function()
        timer_stopped = true
      end,
    }
  end,
}
package.loaded.dropbar = {}

require('local.lazygit').open_lazygit()
local terminal_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds('BufEnter', { buffer = terminal_buf })
assert(timer_callback, 'LazyGit did not start the refresh timer')
assert(
  vim.wait(1500, function()
    local last_line = vim.api.nvim_buf_get_lines(terminal_buf, -2, -1, false)[1] or ''
    return last_line:find('Donate', 1, true) ~= nil
  end),
  'LazyGit did not draw its Donate footer'
)

local original_feedkeys = vim.api.nvim_feedkeys
local injected = {}
vim.api.nvim_feedkeys = function(keys, ...)
  injected[#injected + 1] = keys
  return original_feedkeys(keys, ...)
end
local job = vim.b[terminal_buf].terminal_job_id
vim.api.nvim_chan_send(job, '2')
vim.wait(100)
local panel = vim.api.nvim_buf_get_lines(terminal_buf, 0, 12, false)
if vim.iter(panel):any(function(line)
  return line:find('│▼', 1, true) ~= nil
end) then
  vim.api.nvim_chan_send(job, 'j')
end
vim.api.nvim_chan_send(job, 'e')
assert(
  vim.wait(3000, function()
    return vim.api.nvim_buf_get_name(0) == filename
  end),
  'LazyGit did not open the selected file with e: ' .. vim.inspect(vim.api.nvim_buf_get_lines(terminal_buf, 0, 12, false))
)
-- Model a timer callback already queued when e opened the file.
timer_callback()
assert(#injected == 0, 'LazyGit sent keys to the edited file: ' .. vim.inspect(injected))
assert(timer_stopped, 'LazyGit refresh timer is still running after opening a file')
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'KEEP_ME')

-- While LazyGit is visible, refresh keys must reach its PTY, not global typeahead.
timer_stopped = false
vim.cmd.buffer(terminal_buf)
assert(timer_callback and not timer_stopped)
timer_callback()
vim.api.nvim_feedkeys = original_feedkeys
assert(#injected == 0, 'LazyGit queued keys for Neovim: ' .. vim.inspect(injected))
vim.fn.jobstop(job)
vim.fn.delete(root, 'rf')
print('lazygit timer: ok')
