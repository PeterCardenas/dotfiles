local M = {}

---@param node TSNode
---@param row integer
---@param col integer
---@return boolean
local function is_in_node_range(node, row, col)
  local start_row, start_col, end_row, end_col = node:range()
  if start_row <= row and row <= end_row then
    if start_row == row and end_row == row then
      if start_col <= col and col <= end_col then
        return true
      end
    elseif start_row == row then
      if start_col <= col then
        return true
      end
    elseif end_row == row then
      if col <= end_col then
        return true
      end
    else
      return true
    end
  end
  return false
end

---@return boolean
function M.inside_comment_block()
  if vim.api.nvim_get_mode().mode ~= 'i' then
    return false
  end
  local node_under_cursor = vim.treesitter.get_node()
  local parser = vim.treesitter.get_parser(nil, nil, { error = false })
  local query = vim.treesitter.query.get(vim.bo.filetype, 'highlights')
  if not parser or not node_under_cursor or not query then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  for id, node, _ in query:iter_captures(node_under_cursor, 0, row, row + 1) do
    local capture = query.captures[id]
    if capture:find('comment') and is_in_node_range(node, row, col) then
      return true
    end
  end
  return false
end

---@return boolean
function M.inside_string()
  if vim.api.nvim_get_mode().mode ~= 'i' then
    return false
  end
  local node_under_cursor = vim.treesitter.get_node()
  local parser = vim.treesitter.get_parser(nil, nil, { error = false })
  local query = vim.treesitter.query.get(vim.bo.filetype, 'highlights')
  if not parser or not node_under_cursor or not query then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  for id, node, _ in query:iter_captures(node_under_cursor, 0, row, row + 1) do
    local capture = query.captures[id]
    if capture:find('string') and is_in_node_range(node, row, col) then
      return true
    end
  end
  return false
end

return M
