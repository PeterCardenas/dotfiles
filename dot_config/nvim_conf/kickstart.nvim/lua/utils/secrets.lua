local M = {}

---@param filepath string
---@return boolean, string
function M.read_api_key(filepath)
  local api_key_filepath = vim.fn.expand(filepath)
  ---@type boolean, string[]
  local api_key_ok, api_key_lines = pcall(vim.fn.readfile, api_key_filepath)
  if not api_key_ok or #api_key_lines == 0 or api_key_lines[1] == '' then
    local api_key = vim.fn.input({ prompt = 'Enter key at ' .. api_key_filepath .. ': ', cancelreturn = '' })
    if api_key ~= '' then
      local write_ok, error_msg = require('utils.file').write_to_file(api_key_filepath, api_key)
      if write_ok then
        return true, api_key
      else
        vim.notify('Failed to write key to ' .. api_key_filepath .. (error_msg ~= '' and ': ' .. error_msg or ''), vim.log.levels.ERROR)
        return false, ''
      end
    end
    return false, ''
  end
  return true, api_key_lines[1]
end

return M
