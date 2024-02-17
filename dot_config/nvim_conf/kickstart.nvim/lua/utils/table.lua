local M = {}

--- Merges two tables of the same type
---@generic TTable : table
---@param table_to_override TTable
---@param new_table TTable
---@return TTable
function M.merge_tables(table_to_override, new_table)
  local merged_table = vim.tbl_extend('force', table_to_override, new_table)
  return merged_table
end

return M
