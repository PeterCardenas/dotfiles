-- [[ Logging Utilities ]]
-- Provides safe logging helpers that work in fast events

local M = {}

---Safely notify, scheduling if in a fast event
---@param msg string
---@param level vim.log.levels
local function safe_notify(msg, level)
  local function do_notify()
    vim.notify(msg, level)
  end

  if vim.in_fast_event() then
    vim.schedule(do_notify)
  else
    do_notify()
  end
end

---Log a trace message
---@param msg string
function M.notify_trace(msg)
  safe_notify(msg, vim.log.levels.TRACE)
end

---Log a debug message
---@param msg string
function M.notify_debug(msg)
  safe_notify(msg, vim.log.levels.DEBUG)
end

---Log an info message
---@param msg string
function M.notify_info(msg)
  safe_notify(msg, vim.log.levels.INFO)
end

---Log a warning message
---@param msg string
function M.notify_warn(msg)
  safe_notify(msg, vim.log.levels.WARN)
end

---Log an error message
---@param msg string
function M.notify_error(msg)
  safe_notify(msg, vim.log.levels.ERROR)
end

return M
