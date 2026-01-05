local M = {}

---Safely load plenary.async
local function load_async()
  -- Ensure plenary is in the rtp before requiring
  local plenary_path = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
  if vim.fn.isdirectory(plenary_path) == 1 then
    local rtp = vim.opt.rtp:get()
    local already_in_rtp = false
    for _, path in ipairs(rtp) do
      if path == plenary_path then
        already_in_rtp = true
        break
      end
    end
    if not already_in_rtp then
      vim.opt.rtp:append(plenary_path)
    end
  end

  local ok, async = pcall(require, 'plenary.async')
  if not ok then
    vim.notify('Failed to load plenary.async\n' .. async, vim.log.levels.ERROR)
    return nil
  end
  return async
end

---Immediately executes an async function inside of a sync context.
---@param async_func async fun(): nil
---@return nil
function M.void(async_func)
  local async = load_async()
  if not async then
    return
  end
  async.void(async_func)()
end

---Executes an async function inside of a sync context and calls the callback when done.
---@param async_func async fun(): nil
---@param callback fun(): nil
---@return nil
function M.run(async_func, callback)
  local async = load_async()
  if not async then
    return
  end
  ---@diagnostic disable-next-line: await-in-sync
  async.run(async_func, callback)
end

return M
