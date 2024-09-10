local M = {}

---Get the default branch name of the origin remote.
---@async
---@return boolean, string
function M.get_default_branch()
  local shell = require('utils.shell')
  local success, output = shell.async_cmd('fish', { '-c', 'git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@"' })
  if success then
    return true, output[1]
  end
  success, output = shell.async_cmd('fish', { '-c', 'git remote show origin | grep "HEAD branch" | cut -d ":" -f 2 | string trim' })
  if not success then
    return false, table.concat(output, '\n')
  end
  local default_branch = output[1]
  return true, default_branch
end

return M
