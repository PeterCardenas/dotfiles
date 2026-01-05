local M = {}
local Log = require('utils.log')

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
  -- Add protection against infinite loop
  local max_iterations = 30
  local iterations = 0
  while current_dir ~= '' and current_dir ~= '/' and current_dir ~= home_dir and iterations < max_iterations do
    local current_filepath = current_dir .. '/' .. target_filename
    if vim.fn.isdirectory(current_dir) == 1 and (vim.fn.filereadable(current_filepath) == 1 or vim.fn.isdirectory(current_filepath) == 1) then
      return current_dir
    end
    current_dir = vim.fn.fnamemodify(current_dir, ':h')
    iterations = iterations + 1
  end
  if iterations == max_iterations then
    Log.notify_warn('Could not find ancestor directory of ' .. target_filename .. ' in ' .. current_dir .. ', starting from ' .. start_path)
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
  return vim.startswith(file, directory)
end

--- Writes content to a file, ensuring the directory exists.
---@param filepath string: The path to the file.
---@param content string: The content to write to the file.
---@return boolean, string: Returns true and an empty string on success, or false and an error message on failure.
function M.write_to_file(filepath, content)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if vim.fn.isdirectory(dir) == 0 then
    local mkdir_ok = vim.fn.mkdir(dir, 'p')
    if mkdir_ok == 0 then
      return false, 'Failed to create directory: ' .. dir
    end
  end
  local file = io.open(filepath, 'w+')
  if not file then
    return false, 'Failed to open file'
  end
  local error_msg ---@type string?
  _, error_msg = file:write(content)
  if error_msg ~= nil and error_msg ~= '' then
    return false, 'Failed to write to file: ' .. error_msg
  end
  local success, _, code = file:close()
  if not success then
    return false, 'Failed to close file: ' .. code
  end
  return true, ''
end

---Read a file into a string.
---@param filepath string
---@return string
function M.read_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return ''
  end
  local content = file:read('*a')
  file:close()
  return content
end

return M
