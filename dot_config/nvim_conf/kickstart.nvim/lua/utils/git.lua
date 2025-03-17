local Shell = require('utils.shell')
local M = {}

---Get the default branch name based on whether main or master remote is configured.
---@async
---@return boolean, string
function M.get_default_branch()
  -- Check if main remote is configured.
  local success, _ = Shell.async_cmd('git', { 'config', '--get', 'branch.main.remote' })
  if success then
    return true, 'main'
  end
  success, _ = Shell.async_cmd('git', { 'config', '--get', 'branch.master.remote' })
  if not success then
    return false, 'failed to get default branch'
  end
  return true, 'master'
end

return M
