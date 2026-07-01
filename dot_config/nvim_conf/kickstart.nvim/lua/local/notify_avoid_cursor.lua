---@class notify.AvoidCursor
local M = {}

local stages_util = require('notify.stages.util')

local DIRECTION_VAR = 'notify_avoid_cursor_direction'
local RECENT_INSERT_CURSOR_TTL_MS = 2000
local recent_insert_cursor = nil
local cursor_tracking_group = nil

local function editor_cursor()
  local win_pos = vim.api.nvim_win_get_position(0)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = win_pos[1] + cursor[1] - vim.fn.line('w0') - 1
  local col = win_pos[2] + vim.fn.wincol() - 2
  return row, col
end

local function now_ms()
  return vim.uv.now()
end

local function capture_recent_insert_cursor()
  local ok, row, col = pcall(editor_cursor)
  if not ok then
    return
  end

  recent_insert_cursor = {
    row = row,
    col = col,
    captured_at = now_ms(),
  }
end

local function setup_cursor_tracking()
  if cursor_tracking_group then
    return
  end

  cursor_tracking_group = vim.api.nvim_create_augroup('NotifyAvoidCursorTracking', { clear = true })
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'CursorMovedI', 'TextChangedI' }, {
    group = cursor_tracking_group,
    callback = capture_recent_insert_cursor,
  })
end

---@return { row: integer, col: integer }[]
local function cursor_candidates()
  local candidates = {}
  local ok, row, col = pcall(editor_cursor)
  if ok then
    candidates[#candidates + 1] = { row = row, col = col }
  end

  if recent_insert_cursor and now_ms() - recent_insert_cursor.captured_at <= RECENT_INSERT_CURSOR_TTL_MS then
    local last = candidates[#candidates]
    if not last or last.row ~= recent_insert_cursor.row or last.col ~= recent_insert_cursor.col then
      candidates[#candidates + 1] = {
        row = recent_insert_cursor.row,
        col = recent_insert_cursor.col,
      }
    end
  end

  return candidates
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

  return cursor_row >= top - margin and cursor_row <= bottom + margin and cursor_col >= left - margin and cursor_col <= right + margin
end

---@param row integer NE anchor row (0-based)
---@param col integer NE anchor col (0-based)
---@param height integer
---@param width integer
---@param cursors { row: integer, col: integer }[]
---@return boolean
local function overlaps_any_cursor(row, col, height, width, cursors)
  for _, cursor in ipairs(cursors) do
    if cursor_overlaps_notification(row, col, height, width, cursor.row, cursor.col) then
      return true
    end
  end

  return false
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@param direction string
---@return integer|nil
local function slot_for_direction(state, direction)
  local slot_height = state.message.height + 2
  return stages_util.available_slot(state.open_windows, slot_height, direction)
end

---@param direction string
---@return string
local function opposite_direction(direction)
  return direction == stages_util.DIRECTION.TOP_DOWN and stages_util.DIRECTION.BOTTOM_UP or stages_util.DIRECTION.TOP_DOWN
end

---@param win integer
---@param direction string
local function set_window_direction(win, direction)
  if vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_var, win, DIRECTION_VAR, direction)
  end
end

---@param win integer
---@return string|nil
local function get_window_direction(win)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end

  local ok, direction = pcall(vim.api.nvim_win_get_var, win, DIRECTION_VAR)
  if ok and type(direction) == 'string' then
    return direction
  end

  return nil
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@return string|nil direction
---@return integer|nil row
local function choose_direction_and_row(state)
  local col = vim.opt.columns:get()
  local height = state.message.height
  local width = state.message.width
  local cursors = cursor_candidates()

  local preferred = {
    stages_util.DIRECTION.BOTTOM_UP,
    stages_util.DIRECTION.TOP_DOWN,
  }

  for _, direction in ipairs(preferred) do
    local row = slot_for_direction(state, direction)
    if row and not overlaps_any_cursor(row, col, height, width, cursors) then
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
  local saved_direction = get_window_direction(win)
  if saved_direction then
    return saved_direction
  end

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
  return math.abs(row - top_start) <= math.abs(row - bottom_start) and stages_util.DIRECTION.TOP_DOWN or stages_util.DIRECTION.BOTTOM_UP
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@param win integer
---@param direction string
---@return integer
local function row_for_direction(state, win, direction)
  return stages_util.slot_after_previous(win, state.open_windows, direction)
end

---@param state { message: { height: integer, width: integer }, open_windows: integer[] }
---@param win integer
---@return string
---@return integer
local function live_direction_and_row(state, win)
  local col = vim.opt.columns:get()
  local height = state.message.height
  local width = state.message.width
  local cursors = cursor_candidates()
  local current_direction = direction_for(win)
  local current_row = row_for_direction(state, win, current_direction)

  if not overlaps_any_cursor(current_row, col, height, width, cursors) then
    set_window_direction(win, current_direction)
    return current_direction, current_row
  end

  local alternate_direction = opposite_direction(current_direction)
  local alternate_row = row_for_direction(state, win, alternate_direction)
  if not overlaps_any_cursor(alternate_row, col, height, width, cursors) then
    set_window_direction(win, alternate_direction)
    return alternate_direction, alternate_row
  end

  set_window_direction(win, current_direction)
  return current_direction, current_row
end

---fade_in_slide_out stages with per-notification cursor avoidance.
function M.fade_in_slide_out()
  setup_cursor_tracking()

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
      local _, row = live_direction_and_row(state, win)
      return {
        opacity = { 100 },
        col = { vim.opt.columns:get() },
        row = {
          row,
          frequency = 3,
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      local _, row = live_direction_and_row(state, win)
      return {
        col = { vim.opt.columns:get() },
        time = true,
        row = {
          row,
          frequency = 3,
          complete = function()
            return true
          end,
        },
      }
    end,
    function(state, win)
      local _, row = live_direction_and_row(state, win)
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
          row,
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
