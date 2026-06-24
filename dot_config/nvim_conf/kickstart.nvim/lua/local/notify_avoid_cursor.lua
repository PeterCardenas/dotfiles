---@class notify.AvoidCursor
local M = {}

local stages_util = require('notify.stages.util')

local function editor_cursor()
  local win_pos = vim.api.nvim_win_get_position(0)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = win_pos[1] + cursor[1] - vim.fn.line('w0') - 1
  local col = win_pos[2] + vim.fn.wincol() - 2
  return row, col
end

---@param row integer NE anchor row (0-based)
---@param col integer NE anchor col (0-based)
---@param height integer
---@param width integer
---@param cursor_row integer
---@param cursor_col integer
---@return boolean
local function cursor_overlaps_notification(row, col, height, width, cursor_row, cursor_col)
  local margin = 1
  local top = row
  local bottom = row + height - 1
  local left = col - width + 1
  local right = col

  return cursor_row >= top - margin
    and cursor_row <= bottom + margin
    and cursor_col >= left - margin
    and cursor_col <= right + margin
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@param direction string
---@return integer|nil
local function slot_for_direction(state, direction)
  local slot_height = state.message.height + 2
  return stages_util.available_slot(state.open_windows, slot_height, direction)
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@return string|nil direction
---@return integer|nil row
local function choose_direction_and_row(state)
  local col = vim.opt.columns:get()
  local height = state.message.height
  local width = state.message.width
  local cursor_row, cursor_col = editor_cursor()

  local preferred = {
    stages_util.DIRECTION.BOTTOM_UP,
    stages_util.DIRECTION.TOP_DOWN,
  }

  for _, direction in ipairs(preferred) do
    local row = slot_for_direction(state, direction)
    if row and not cursor_overlaps_notification(row, col, height, width, cursor_row, cursor_col) then
      return direction, row
    end
  end

  for _, direction in ipairs(preferred) do
    local row = slot_for_direction(state, direction)
    if row then
      return direction, row
    end
  end

  return nil, nil
end

---Infer stack direction from the row chosen in stage 1 so later stages do not flip stacks.
---@param win integer
---@return string
local function direction_for(win)
  if not vim.api.nvim_win_is_valid(win) then
    return stages_util.DIRECTION.BOTTOM_UP
  end

  local ok, conf = pcall(vim.api.nvim_win_get_config, win)
  if not ok or conf.row == nil then
    return stages_util.DIRECTION.BOTTOM_UP
  end

  local row = conf.row
  if type(row) == 'table' then
    row = row[false] or row[1]
  end

  local top_start = stages_util.get_slot_range(stages_util.DIRECTION.TOP_DOWN)
  local bottom_start = stages_util.get_slot_range(stages_util.DIRECTION.BOTTOM_UP)
  return math.abs(row - top_start) <= math.abs(row - bottom_start)
      and stages_util.DIRECTION.TOP_DOWN
    or stages_util.DIRECTION.BOTTOM_UP
end

---fade_in_slide_out stages with per-notification cursor avoidance.
function M.fade_in_slide_out()
  return {
    function(state)
      local direction, next_row = choose_direction_and_row(state)
      if not direction or not next_row then
        return nil
      end
      return {
        relative = 'editor',
        anchor = 'NE',
        width = state.message.width,
        height = state.message.height,
        col = vim.opt.columns:get(),
        row = next_row,
        border = 'rounded',
        style = 'minimal',
        opacity = 0,
      }
    end,
    function(state, win)
      local direction = direction_for(win)
      return {
        opacity = { 100 },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 3,
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      local direction = direction_for(win)
      return {
        col = { vim.opt.columns:get() },
        time = true,
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 3,
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      local direction = direction_for(win)
      return {
        width = {
          1,
          frequency = 2.5,
          damping = 0.9,
          complete = function(cur_width)
            return cur_width < 3
          end,
        },
        opacity = {
          0,
          frequency = 2,
          complete = function(cur_opacity)
            return cur_opacity <= 4
          end,
        },
        col = { vim.opt.columns:get() },
        row = {
          stages_util.slot_after_previous(win, state.open_windows, direction),
          frequency = 3,
          complete = function()
            return true
          end,
        },
      }
    end,
  }
end

return M
