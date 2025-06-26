local M = {}

---@param include_current boolean
---@return integer[]
function M.get_navigable_buffers(include_current)
  ---@type integer[]
  local bufnrs = vim.tbl_filter(function(bufnr) ---@param bufnr integer
    if 1 ~= vim.fn.buflisted(bufnr) then
      return false
    end
    if bufnr == vim.api.nvim_get_current_buf() and not include_current then
      return false
    end

    return true
  end, vim.api.nvim_list_bufs())

  table.sort(bufnrs, function(a, b)
    return vim.fn.getbufinfo(a)[1].lastused > vim.fn.getbufinfo(b)[1].lastused
  end)
  return bufnrs
end

---@param bufnr integer
---@param file_size_threshold integer
---@return boolean
function M.is_buf_large(bufnr, file_size_threshold)
  local file_name = vim.api.nvim_buf_get_name(bufnr)
  local file_size = vim.fn.getfsize(file_name)
  return file_size > file_size_threshold
end

function M.close_current_buffer()
  local navigable_bufnrs = M.get_navigable_buffers(true)
  require('bufdelete').bufdelete()
  if #navigable_bufnrs == 1 then
    local alpha = require('alpha')
    alpha.start(false, alpha.default_config)
    -- TODO: remove annoying scratch buffer that gets created here
  end
end

return M
