local String = require('utils.string')
M = {}

---Run a shell command synchronously and return the output.
---@param cmd string
---@return boolean, string[]
function M.sync_cmd(cmd)
  local result = vim.fn.system(cmd)
  local output = String.split_lines(result)
  return vim.v.shell_error == 0, output
end

---@type (async fun(cmd: string, args: string[], cwd: string | nil): (boolean, string[])) | nil
local cached_async_cmd = nil

local function get_async_cmd()
  if cached_async_cmd == nil then
    local async = require('plenary.async')
    cached_async_cmd = async.wrap(
      ---@param cmd string
      ---@param args string[]
      ---@param cwd string | nil
      ---@param done fun(success: boolean, output: string[])
      ---@return nil
      function(cmd, args, cwd, done)
        local Job = require('plenary.job')

        ---@type string[]
        local output = {}
        ---@param data string
        local function handle_output(data)
          if data then
            local lines = String.split_lines(data)
            vim.list_extend(output, lines)
          end
        end
        ---@diagnostic disable-next-line: missing-fields
        local job = Job:new({
          command = cmd,
          args = args,
          on_stdout = function(_, data)
            handle_output(data)
          end,
          on_stderr = function(_, data)
            handle_output(data)
          end,
          on_exit = function(_, code)
            ---@type boolean, string
            local ok, err = pcall(done, code == 0, output)
            if not ok then
              vim.schedule(function()
                vim.notify(
                  'Error calling done callback:' .. err .. '\ncmd: ' .. cmd .. '\nargs: ' .. vim.inspect(args) .. '\nOutput: ' .. table.concat(output, '\n'),
                  vim.log.levels.ERROR
                )
              end)
            end
          end,
          env = vim.tbl_extend('force', vim.fn.environ(), {
            GH_TOKEN = GH_TOKEN,
          }),
          cwd = cwd,
        })
        job:start()
      end,
      4
    )
  end
  return cached_async_cmd
end

---Run a shell command asynchronously and return the output.
---@async
---@param cmd string
---@param args string[]
---@param cwd? string
---@return boolean, string[]
function M.async_cmd(cmd, args, cwd)
  local async_cmd = get_async_cmd()
  return async_cmd(cmd, args, cwd)
end

---@type async fun(ms: number)
local cached_sleep = nil

local get_cached_sleep = function()
  if cached_sleep == nil then
    local async = require('plenary.async')
    cached_sleep = async.wrap(
      ---@param ms number
      ---@param done fun(): nil
      function(ms, done)
        vim.defer_fn(function()
          done()
        end, ms)
      end,
      2
    )
  end
  return cached_sleep
end

---Sleep asynchrnously for a given number of milliseconds.
---@async
---@param ms number
function M.sleep(ms)
  return get_cached_sleep()(ms)
end

return M
