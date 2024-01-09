local M = {}

---@param name string
---@return boolean
function M.file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  end
  return false
end

---@return string
function M.get_cwd()
  return os.getenv('PWD') or io.popen('cd'):read()
end

return M
