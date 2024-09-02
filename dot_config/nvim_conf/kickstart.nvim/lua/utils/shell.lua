local async = require('plenary.async')
local Job = require('plenary.job')

M = {}

---Run a shell command and throw an error if it fails. Return the output of the command if successful.
---@param cmd string
---@return string
function M.strict_cmd(cmd)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error({ message = 'Command failed', cmd = cmd, output = result, error_code = vim.v.shell_error })
  end
  return result
end

---Run a shell command synchronously and return the output.
---@param cmd string
---@return boolean, string[]
function M.sync_cmd(cmd)
  local result = vim.fn.system(cmd)
  local output = require('utils.string').split_lines(result)
  return vim.v.shell_error == 0, output
end

---Run a shell command asynchronously and return the output.
---@type async fun(cmd: string, args: string[]): (boolean, string[])
M.async_cmd = async.wrap(
  ---@param cmd string
  ---@param args string[]
  ---@param done fun(success: boolean, output: string[])
  ---@return nil
  function(cmd, args, done)
    Job:new({
      command = cmd,
      args = args,
      on_exit = function(self, code)
        -- TODO: Use on_stderr and on_stdout to make the stderr and stdout come in order when aggregated.
        local output = vim.list_extend({}, self:result())
        output = vim.list_extend(output, self:stderr_result())
        done(code == 0, output)
      end,
    }):start()
  end,
  3
)

---Sleep asynchrnously for a given number of milliseconds.
---@type async fun(ms: number)
M.sleep = async.wrap(
  ---@param ms number
  ---@param done fun(): nil
  function(ms, done)
    vim.defer_fn(function()
      done()
    end, ms)
  end,
  2
)

return M
