local Shell = require('utils.shell')
local Async = require('utils.async')

local M = {}

M.AWS_REGION = 'us-east-1'

---@alias AWSLoginInfo { access_key_id: string, secret_access_key: string, session_token: string }

---@type AWSLoginInfo?
local cached_login_info = nil

---@param cb? fun(login_info: AWSLoginInfo?): nil
---@return AWSLoginInfo?
function M.get_aws_login_info(cb)
  if cached_login_info then
    if cb then
      return cb(cached_login_info)
    end
    return cached_login_info
  end
  local wrapped_cb = cb or function() end
  local cmd = 'aws'
  local function get_config_args(key)
    return { 'configure', 'get', key, '--profile', 'default', '--region', M.AWS_REGION }
  end

  Async.void(function() ---@async
    local success, output = Shell.async_cmd(cmd, get_config_args('aws_access_key_id'))
    local access_key_id = ''
    if success then
      access_key_id = output[1]
    else
      vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      return wrapped_cb(nil)
    end

    success, output = Shell.async_cmd(cmd, get_config_args('aws_secret_access_key'))
    local secret_access_key = ''
    if success then
      secret_access_key = output[1]
    else
      vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      return wrapped_cb(nil)
    end

    success, output = Shell.async_cmd(cmd, get_config_args('aws_session_token'))
    local session_token = ''
    if success then
      session_token = output[1]
    else
      vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      return wrapped_cb(nil)
    end

    cached_login_info = {
      access_key_id = access_key_id,
      secret_access_key = secret_access_key,
      session_token = session_token,
    }
    return wrapped_cb(cached_login_info)
  end)
  if cb then
    return nil
  end
  vim.wait(10000, function()
    return cached_login_info ~= nil
  end, 10)
  return cached_login_info
end

return M
