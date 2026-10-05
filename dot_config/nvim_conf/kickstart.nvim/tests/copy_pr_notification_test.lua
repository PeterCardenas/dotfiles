local root = vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim'
vim.opt.rtp:prepend(root)

local Shell = require('utils.shell')
local original_async_cmd = Shell.async_cmd
Shell.async_cmd = function(cmd, ...)
  if cmd == 'gh' then
    return true,
      {
        vim.json.encode({
          number = 1,
          url = 'https://github.com/example/repo/pull/1',
          title = 'CopyPR test',
          additions = 3,
          deletions = 2,
        }),
      }
  end
  return original_async_cmd(cmd, ...)
end

package.loaded['octo.utils'] = {
  get_current_buffer = function()
    return nil
  end,
}
local notified
require('utils.log').notify_info = function(message)
  notified = message
end

dofile(root .. '/lua/plugins/gitsigns.lua')
vim.cmd.CopyPR()
assert(
  vim.wait(2000, function()
    return notified ~= nil
  end, 10),
  'CopyPR copied HTML but never displayed the success notification'
)
assert(notified:find('Copied PR as markdown:', 1, true), notified)
print('CopyPR notification displayed after clipboard copy')
