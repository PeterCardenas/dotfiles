local M = {}

---Open a file path, or a URL in the system's default application.
---Returns whether the operation was successful.
---@param uri string
---@param quiet? boolean
---@return boolean
function M.system_open(uri, quiet)
  quiet = quiet or false
  if vim.fn.empty(vim.fn.getenv('SSH_CONNECTION')) == 0 then
    if not quiet then
      vim.notify("system_open is not supported in SSH sessions", vim.log.levels.ERROR,
        { title = "System Open" })
    end
    return false
  end
  if vim.fn.has("mac") == 1 then
    -- if mac use the open command
    vim.fn.jobstart({ "open", uri }, { detach = true })
  elseif vim.fn.has("unix") == 1 then
    -- if unix then use xdg-open
    vim.fn.jobstart({ "xdg-open", uri }, { detach = true })
  else
    if not quiet then
      vim.notify("System open is not supported on this OS!", vim.log.levels.ERROR,
        { title = "System Open" })
    end
    return false
  end
  return true
end

return M
