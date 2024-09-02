local M = {}

---Trim whitespace from the beginning and end of a string.
---@param s string
---@return string
function M.trim(s)
  return (s:gsub('^%s*(.-)%s*$', '%1'))
end

---Split a string by newlines.
---@param s string
---@return string[]
function M.split_lines(s)
  s = s:gsub('\r\n', '\n')
  return vim.split(s, '\n')
end

return M
