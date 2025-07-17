local M = {}

---@param pattern string|string[]
function M.create_spinner(pattern)
  ---@type Anime
  local spinner
  return function()
    if not spinner then
      spinner = require('fidget').spinner.animate(pattern)
    end
    return spinner(vim.uv.now() / 1000.0)
  end
end

---@return { start: (fun(cb: (fun(): nil)): nil), stop: (fun(): nil) }
function M.create_timer()
  local timer = vim.uv.new_timer()
  return {
    ---@param cb fun(): nil
    start = function(cb)
      timer:start(0, 16, vim.schedule_wrap(cb))
    end,
    stop = function()
      timer:stop()
    end,
  }
end

return M
