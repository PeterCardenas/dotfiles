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

function M.get_ancestor_dir(target_filename, start_path)
  local target_dir = M.get_cwd()
  if start_path ~= nil then
    if vim.fn.isdirectory(start_path) == 1 then
      target_dir = start_path
    else
      target_dir = vim.fn.fnamemodify(start_path, ':h')
    end
  end
  local home_dir = os.getenv('HOME')
  while target_dir ~= '' and target_dir ~= home_dir do
    local ancestor_dir = target_dir .. '/' .. target_filename
    if vim.fn.isdirectory(ancestor_dir) == 1 or vim.fn.filereadable(ancestor_dir) then
      return target_dir
    end
    target_dir = vim.fn.fnamemodify(target_dir, ':h')
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
