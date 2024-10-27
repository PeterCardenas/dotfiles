local M = {}

---Merges two tables of the same type
---@generic TTable : table
---@param table_to_override TTable
---@param new_table TTable
---@return TTable
function M.merge_tables(table_to_override, new_table)
  local merged_table = vim.tbl_extend('force', table_to_override, new_table)
  return merged_table
end

---Removes duplicates from a list
---@generic TList : table
---@param list TList
---@return TList
function M.remove_duplicates(list)
  local seen = {}
  local new_list = {}
  for _, v in ipairs(list) do
    if not seen[v] then
      table.insert(new_list, v)
      seen[v] = true
    end
  end
  return new_list
end

return M
