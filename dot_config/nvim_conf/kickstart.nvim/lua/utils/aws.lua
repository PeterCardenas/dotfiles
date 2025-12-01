local Shell = require('utils.shell')

local M = {}

M.AWS_REGION = 'us-east-1'

---@alias AWSLoginInfo { access_key_id: string, secret_access_key: string, session_token: string }

---@type AWSLoginInfo?
local cached_login_info = nil

---@return AWSLoginInfo?
function M.get_aws_login_info()
  if cached_login_info then
    return cached_login_info
  end
  local base_args = 'aws configure get '
  local specific_args = ' --profile default --region ' .. M.AWS_REGION

  local success, output = Shell.sync_cmd(base_args .. 'aws_access_key_id' .. specific_args)
  local access_key_id = ''
  if success then
    access_key_id = output[1]
  else
    vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    return nil
  end

  success, output = Shell.sync_cmd(base_args .. 'aws_secret_access_key' .. specific_args)
  local secret_access_key = ''
  if success then
    secret_access_key = output[1]
  else
    vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    return nil
  end

  success, output = Shell.sync_cmd(base_args .. 'aws_session_token' .. specific_args)
  local session_token = ''
  if success then
    session_token = output[1]
  else
    vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    return nil
  end

  cached_login_info = {
    access_key_id = access_key_id,
    secret_access_key = secret_access_key,
    session_token = session_token,
  }
  return cached_login_info
end

return M
