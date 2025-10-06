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

---@class SpinnerTimer
---@field start fun(cb: (fun(): nil)): nil
---@field stop fun(): nil

---@return SpinnerTimer
function M.create_timer()
  local timer = vim.uv.new_timer()
  local is_cleared = false
  return {
    ---@param cb fun(): nil
    start = function(cb)
      timer:start(
        0,
        16,
        vim.schedule_wrap(function()
          if is_cleared then
            return
          end
          cb()
        end)
      )
    end,
    stop = function()
      is_cleared = true
      timer:stop()
      timer:close()
    end,
  }
end

return M
