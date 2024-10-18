local M = {}

---Get the default branch name of the origin remote.
---@async
---@return boolean, string
function M.get_default_branch()
  local shell = require('utils.shell')
  -- Try a local git command first for max speed.
  local success, output =
    shell.async_cmd('fish', { '-c', 'git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@"; test $pipestatus[1] -eq 0' })
  if success then
    return true, output[1]
  end
  -- Try github cli as a fallback.
  -- TODO: This requires that a default repo is selected, would be nice to allow selection ad hoc when not set.
  success, output = shell.async_cmd('gh', { 'repo', 'view', '--json', 'defaultBranchRef', '--jq', '.defaultBranchRef.name' })
  if not success then
    return false, table.concat(output, '\n')
  end
  local default_branch = output[1]
  return true, default_branch
end

return M
