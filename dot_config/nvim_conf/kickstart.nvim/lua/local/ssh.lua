local M = {}

---@param args string[]
---@param alias string
function M.execute_ssh_command(alias, args)
  local Job = require('plenary.job')
  ---@diagnostic disable-next-line: missing-fields
  local job = Job:new({
    command = 'ssh',
    args = { '-tt', alias, table.concat(args, ' ') },
    on_exit = function(_self, code)
      if code ~= 0 then
        vim.notify('ssh command failed', vim.log.levels.ERROR)
      end
    end,
  })
  job:start()
end

return M
