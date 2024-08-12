local M = {}

---Get the default branch name of the origin remote.
---@return string
function M.get_default_branch()
  local default_branch = vim.fn.systemlist('git symbolic-ref refs/remotes/origin/HEAD | sed "s@^refs/remotes/origin/@@"')[1]
  return default_branch
end

return M
