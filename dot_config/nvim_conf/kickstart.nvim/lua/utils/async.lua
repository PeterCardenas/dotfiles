local M = {}

---Immediately executes an async function inside of a sync context.
---@param async_func async fun(): nil
---@return nil
function M.void(async_func)
  local async = require('plenary.async')
  async.void(async_func)()
end

---Executes an async function inside of a sync context and calls the callback when done.
---@param async_func async fun(): nil
---@param callback fun(): nil
---@return nil
function M.run(async_func, callback)
  local async = require('plenary.async')
  ---@diagnostic disable-next-line: await-in-sync
  async.run(async_func, callback)
end

return M
