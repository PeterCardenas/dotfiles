local M = {}

---Get the default branch name of the origin remote.
---@async
---@return string
function M.get_default_branch()
  local shell = require('utils.shell')
  local _, output = shell.async_cmd('fish', { '-c', 'git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@"' })
  local default_branch = output[1]
  return default_branch
end

return M
