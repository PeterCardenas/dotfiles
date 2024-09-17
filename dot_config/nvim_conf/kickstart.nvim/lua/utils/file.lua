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

---@param target_filename string
---@param start_path string | nil
---@return string | nil
function M.get_ancestor_dir(target_filename, start_path)
  local current_dir = M.get_cwd()
  if start_path ~= nil then
    if vim.fn.isdirectory(start_path) == 1 then
      current_dir = start_path
    else
      current_dir = vim.fn.fnamemodify(start_path, ':h')
    end
  end
  local home_dir = os.getenv('HOME')
  while current_dir ~= '' and current_dir ~= '/' and current_dir ~= home_dir do
    local current_filepath = current_dir .. '/' .. target_filename
    if vim.fn.isdirectory(current_dir) == 1 and (vim.fn.filereadable(current_filepath) == 1 or vim.fn.isdirectory(current_filepath) == 1) then
      return current_dir
    end
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
  end
  return nil
end

---Gets the directory of the git root from the given file/directory.
---This avoids using other plugins for startup time.
---@param file_or_dir string? If not given, the current working directory is used.
---@return string|nil
function M.get_git_root(file_or_dir)
  return M.get_ancestor_dir('.git', file_or_dir)
end

---Checks whether the given file is in the given directory.
---@param file string
---@param directory string
---@return boolean
function M.file_in_directory(file, directory)
  return file:find(directory, 1, true) == 1
end

return M
