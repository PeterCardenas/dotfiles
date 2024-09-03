local async = require('plenary.async')
local Job = require('plenary.job')

M = {}

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
    ---@type string[]
    local output = {}
    ---@param data string
    local function handle_output(data)
      if data then
        local lines = require('utils.string').split_lines(data)
        vim.list_extend(output, lines)
      end
    end
    Job:new({
      command = cmd,
      args = args,
      on_stdout = function(_, data)
        handle_output(data)
      end,
      on_stderr = function(_, data)
        handle_output(data)
      end,
      on_exit = function(_, code)
        -- TODO: Use on_stderr and on_stdout to make the stderr and stdout come in order when aggregated.
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
