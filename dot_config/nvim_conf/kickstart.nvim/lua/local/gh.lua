local Async = require('utils.async')
local Log = require('utils.log')
local Shell = require('utils.shell')

---@async
local function get_gh_user()
  local ok, output = Shell.async_cmd('git', { 'config', '--get', 'remote.origin.url' })
  if not ok then
    return 'PeterCardenas'
  end
  local url = output[1]
  return url:match('^work%-github%.com') ~= nil and 'peter-cardenas-ai' or 'PeterCardenas'
end

---@async
local function set_gh_user()
  local gh_user = get_gh_user()
  local ok, output = Shell.async_cmd('gh', { 'auth', 'token', '--user', gh_user })
  if not ok then
    Log.notify_error(table.concat(output, '\n'))
  end
  local gh_token = output[1]
  _G.GH_TOKEN = gh_token
  vim.schedule(function()
    vim.env.GH_TOKEN = gh_token
  end)
end

-- Run immediately — only needs async shell commands, no plugin dependencies.
Async.void(set_gh_user)
