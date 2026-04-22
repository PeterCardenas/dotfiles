local M = {}

---@param pattern string|string[]
local function create_spinner(pattern)
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
  if not timer then
    error('Failed to create timer')
  end
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
      pcall(function()
        timer:close()
      end)
    end,
  }
end

---@class SpinnerProgressHandle
---@field handle ProgressHandle
---@field current_message string
---@field spinner? fun(): string
---@field timer? SpinnerTimer
local SpinnerProgressHandle = {}
SpinnerProgressHandle.__index = SpinnerProgressHandle

---@class SpinnerProgressOptions
---@field group string
---@field message string
---@field pattern? string|string[]

---@param group string
local function hide_group_header(group)
  local notification = require('fidget.notification')
  local config = require('fidget.progress.display').make_config(group)
  config.name = false
  config.icon = false
  config.ttl = 1
  config.annote_separator = ''
  config.update_hook = function(item)
    local payload = item.message
    item.message = ' '
    item.annote = payload
    -- TODO: Change styling with a "status" payload to distinguish
    if item.data then
      item.style = config.info_style or 'Constant'
    else
      item.style = config.warn_style or config.annote_style or 'WarningMsg'
    end
    notification.set_content_key(item)
  end
  notification.set_config(group, config, true)
end

---@param spinner (fun(): string)?
---@param message string
---@return string
local function format_message(spinner, message)
  if not spinner then
    return message
  end
  return spinner() .. ' ' .. message
end

---@param message string
---@return string
function SpinnerProgressHandle:format_message(message)
  return format_message(self.spinner, message)
end

function SpinnerProgressHandle:stop_timer()
  if not self.timer then
    return
  end
  self.timer:stop()
  self.timer = nil
end

---@param opts SpinnerProgressOptions
---@return SpinnerProgressHandle
function SpinnerProgressHandle:new(opts)
  hide_group_header(opts.group)

  local progress = require('fidget.progress')
  local current_message = opts.message
  local handle = progress.handle.create({
    message = self:format_message(current_message),
    lsp_client = { name = opts.group },
  })
  ---@type SpinnerProgressHandle
  local instance = {
    spinner = opts.pattern and create_spinner(opts.pattern) or nil,
    current_message = current_message,
    handle = handle,
  }
  setmetatable(instance, self)

  if instance.spinner then
    instance.timer = M.create_timer()
    instance.timer.start(function()
      if instance.handle.done then
        instance:stop_timer()
        return
      end
      instance.handle:report({ message = instance:format_message(instance.current_message) })
    end)
  end

  return instance
end

---@param message string
function SpinnerProgressHandle:report(message)
  self.current_message = message
  self.handle:report({
    message = self:format_message(self.current_message),
  })
end

---@param message? string
function SpinnerProgressHandle:finish(message)
  self:stop_timer()
  if message then
    self.current_message = message
    self.handle:report({ message = message })
  end
  self.handle:finish()
end

---@param opts SpinnerProgressOptions
---@return SpinnerProgressHandle
function M.create_progress_handle(opts)
  return SpinnerProgressHandle:new(opts)
end

return M
