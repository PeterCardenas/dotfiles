---@async
local function get_gh_user()
  local shell = require('utils.shell')
  local ok, output = shell.async_cmd('git', { 'config', '--get', 'remote.origin.url' })
  if not ok then
    return 'PeterCardenas'
  end
  local url = output[1]
  return url:match('^work%-github%.com') ~= nil and 'peter-cardenas-ai' or 'PeterCardenas'
end

---@async
local function set_gh_user()
  local gh_user = get_gh_user()
  local shell = require('utils.shell')
  local ok, output = shell.async_cmd('gh', { 'auth', 'token', '--user', gh_user })
  if not ok then
    vim.schedule(function()
      vim.notify(table.concat(output, '\n'), vim.log.levels.ERROR)
    end)
  end
  local gh_token = output[1]
  _G.GH_TOKEN = gh_token
  vim.schedule(function()
    vim.env.GH_TOKEN = gh_token
  end)
end

-- Set on LazyDone so that plugins are loaded
vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyDone',
  once = true,
  desc = 'Set up user for gh cli',
  group = vim.api.nvim_create_augroup('set_gh_user', { clear = true }),
  callback = function()
    local async = require('utils.async')
    async.void(set_gh_user)
  end,
})
