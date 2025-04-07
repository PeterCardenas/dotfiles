local M = {}

---Merges two tables of the same type one level deep
---@generic TTable : table
---@param table_to_override TTable
---@param new_table TTable
---@return TTable
function M.merge_tables(table_to_override, new_table)
  local merged_table = vim.tbl_extend('force', table_to_override, new_table)
  return merged_table
end

---Removes duplicates from a list
---@generic TItem: any
---@param list TItem[]
---@param predicate? fun(item: TItem): any
---@return TItem[]
function M.remove_duplicates(list, predicate)
  local seen = {} ---@type table<any, boolean>
  local new_list = {}
  ---@diagnostic disable-next-line: no-unknown
  for _, v in ipairs(list) do
    local index = predicate and predicate(v) or v
    if not seen[index] then
      new_list[#new_list + 1] = v ---@type any
      seen[index] = true
    end
  end
  return new_list
end

return M
