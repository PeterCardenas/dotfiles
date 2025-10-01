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

---@param bufnr? integer
---@param row? integer
---@param col? integer
---@return TSNode?, vim.treesitter.LanguageTree?, vim.treesitter.Query?
local function get_ts_info(bufnr, row, col)
  if (row and (not bufnr or row < 1 or row > vim.api.nvim_buf_line_count(bufnr))) or (col and col < 1) then
    return nil, nil, nil
  end
  local node_under_cursor = vim.treesitter.get_node({
    bufnr = bufnr,
    pos = bufnr and { row, col },
  })
  local parser = vim.treesitter.get_parser(nil, nil, { error = false })
  if not parser or not node_under_cursor then
    return node_under_cursor, parser, nil
  end
  local query = vim.treesitter.query.get(parser:lang(), 'highlights')
  return node_under_cursor, parser, query
end

---@return boolean
function M.has_treesitter()
  return vim.treesitter.get_parser(nil, nil, { error = false }) ~= nil
end

---@param bufnr? integer
---@param row? integer
---@param col? integer
---@return boolean
function M.inside_comment_block(bufnr, row, col)
  local node_under_cursor, parser, query = get_ts_info(bufnr, row, col)
  if not node_under_cursor or not parser or not query then
    return false
  end
  if node_under_cursor:type():find('comment') then
    return true
  end
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  cursor_row = cursor_row - 1
  row = row or cursor_row
  col = col or cursor_col
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
  local node_under_cursor, parser, query = get_ts_info()
  if not parser or not node_under_cursor or not query then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  if node_under_cursor:type():find('string') then
    return true
  end
  for id, node, _ in query:iter_captures(node_under_cursor, 0, row, row + 1) do
    local capture = query.captures[id]
    if capture:find('string') and is_in_node_range(node, row, col) then
      return true
    end
  end
  return false
end

return M
