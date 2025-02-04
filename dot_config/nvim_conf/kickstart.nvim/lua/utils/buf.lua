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

return M
