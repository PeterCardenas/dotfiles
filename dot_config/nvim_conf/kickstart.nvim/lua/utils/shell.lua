M = {}

---Run a shell command and throw an error if it fails. Return the output of the command if successful.
---@param cmd string
---@return string
function M.strict_cmd(cmd)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error('Failed to run command: ' .. cmd .. ', output: ' .. result)
  end
  return result
end

return M
