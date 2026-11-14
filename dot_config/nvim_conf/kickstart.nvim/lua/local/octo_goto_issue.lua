local M = {}

---@param winid integer
---@return boolean
local function is_floating(winid)
  return vim.api.nvim_win_get_config(winid).relative ~= ''
end

-- Floats (hover popups, zen-mode, etc.) are transient, so issues opened from
-- them belong in the window the float was entered from. Falls back to any
-- non-floating window when the previous window is itself a float.
---@return integer
local function target_window()
  local current_winid = vim.api.nvim_get_current_win()
  if not is_floating(current_winid) then
    return current_winid
  end
  local previous_winnr = vim.fn.winnr('#')
  if previous_winnr > 0 then
    local previous_winid = vim.fn.win_getid(previous_winnr)
    if previous_winid ~= 0 and not is_floating(previous_winid) then
      return previous_winid
    end
  end
  local fallback_winid = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(winid)
    return not is_floating(winid)
  end)
  return fallback_winid or current_winid
end

-- Replaces octo's goto_issue mapping so floats don't swallow the opened buffer.
function M.go_to_issue()
  local utils = require('octo.utils')
  local repo, number = utils.extract_issue_at_cursor(utils.get_current_repo())
  if not repo or not number then
    return
  end
  local winid = target_window()
  vim.api.nvim_set_current_win(winid)
  utils.open_buffer(repo, number, { winid = winid })
end

return M
