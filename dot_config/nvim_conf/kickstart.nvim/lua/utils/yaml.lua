local M = {}

---@param filename string
---@return boolean
function M.is_template_filename(filename)
  return filename:match('template%.yaml$') ~= nil or filename:match('%.yaml%.tpl$') ~= nil
end

---@param bufnr integer
---@return boolean
function M.has_jinja_template_syntax(bufnr)
  if vim.bo[bufnr].filetype ~= 'yaml' then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find('{{', 1, true) or line:find('{%', 1, true) then
      return true
    end
  end
  return false
end

---@param bufnr integer
---@return boolean
function M.is_jinja_template_buffer(bufnr)
  if vim.bo[bufnr].filetype ~= 'yaml' then
    return false
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return M.is_template_filename(filename) or M.has_jinja_template_syntax(bufnr)
end

return M
