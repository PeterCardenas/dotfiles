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

---Gets the directory of the git root from the given file/directory.
---This avoids using other plugins for startup time.
---@param file_or_dir string? If not given, the current working directory is used.
---@return string|nil
function M.get_git_root(file_or_dir)
  local target_dir = vim.fn.getcwd()
  if file_or_dir ~= nil then
    if vim.fn.isdirectory(file_or_dir) == 1 then
      target_dir = file_or_dir
    else
      target_dir = vim.fn.fnamemodify(file_or_dir, ':h')
    end
  end
  local home_dir = vim.fn.expand('~')
  while target_dir ~= '' and target_dir ~= home_dir do
    local git_dir = target_dir .. '/.git'
    if vim.fn.isdirectory(git_dir) == 1 then
      return target_dir
    end
    target_dir = vim.fn.fnamemodify(target_dir, ':h')
  end
  return nil
end

---Checks whether the given file is in the given directory.
---@param file string
---@param directory string
---@return boolean
function M.file_in_directory(file, directory)
  return file:find(directory, 1, true) == 1
end

return M
