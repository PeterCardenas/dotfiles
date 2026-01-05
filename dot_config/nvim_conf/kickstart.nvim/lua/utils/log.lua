-- [[ Logging Utilities ]]
-- Provides safe logging helpers that work in fast events

local M = {}

---@class NotifyOpts
---@field title? string

---Safely notify, scheduling if in a fast event
---@param msg string
---@param level vim.log.levels
---@param opts? NotifyOpts
local function safe_notify(msg, level, opts)
  local function do_notify()
    vim.notify(msg, level, opts)
  end

  if vim.in_fast_event() then
    vim.schedule(do_notify)
  else
    do_notify()
  end
end

---Log a trace message
---@param msg string
---@param opts? NotifyOpts
function M.notify_trace(msg, opts)
  safe_notify(msg, vim.log.levels.TRACE, opts)
end

---Log a debug message
---@param msg string
---@param opts? NotifyOpts
function M.notify_debug(msg, opts)
  safe_notify(msg, vim.log.levels.DEBUG, opts)
end

---Log an info message
---@param msg string
---@param opts? NotifyOpts
function M.notify_info(msg, opts)
  safe_notify(msg, vim.log.levels.INFO, opts)
end

---Log a warning message
---@param msg string
---@param opts? NotifyOpts
function M.notify_warn(msg, opts)
  safe_notify(msg, vim.log.levels.WARN, opts)
end

---Log an error message
---@param msg string
---@param opts? NotifyOpts
function M.notify_error(msg, opts)
  safe_notify(msg, vim.log.levels.ERROR, opts)
end

return M
