local Buf = require('utils.buf')

local M = {}
local ns_previewer = vim.api.nvim_create_namespace('fzf_buffer_picker_previewer')

---@class FzfBufferPickerEntry
---@field bufnr integer
---@field buftype string
---@field is_octo boolean
---@field lnum integer
---@field path string
---@field preview_title string
---@field line string

---@type table<string, FzfBufferPickerEntry>
local entry_lookup = {}

---@param bufnr integer
---@return integer
local function current_lnum(bufnr)
  local info = vim.fn.getbufinfo(bufnr)[1]
  local lnum = info and info.lnum or 1
  if lnum == 0 then
    return 1
  end

  if vim.api.nvim_buf_is_loaded(bufnr) then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    return math.max(math.min(lnum, line_count), 1)
  end
  return lnum
end

---@param bufnr integer
---@return table|nil
local function get_octo_buffer(bufnr)
  return _G.octo_buffers and _G.octo_buffers[bufnr] or nil
end

---@param bufnr integer
---@param path string
---@return string, boolean
local function display_name(bufnr, path)
  local octo_buf = get_octo_buffer(bufnr)
  if octo_buf ~= nil then
    local title = octo_buf.titleMetadata and octo_buf.titleMetadata.body or ''
    if title ~= '' then
      return title, true
    end
  end

  if path == '' then
    return '[No Name]', false
  end

  return vim.fn.fnamemodify(path, ':~:.'), false
end

---@param bufnr integer
---@param path string
---@return boolean
local function is_missing_buffer(bufnr, path)
  local buftype = vim.bo[bufnr].buftype
  return buftype ~= 'terminal' and buftype ~= 'acwrite' and buftype ~= 'nofile' and path ~= '' and vim.fn.filereadable(vim.fn.fnamemodify(path, ':p')) == 0
end

---@param bufnr integer
---@param path string
---@param is_octo boolean
---@return string
local function icon_display(bufnr, path, is_octo)
  local utils = require('fzf-lua.utils')
  if is_octo then
    return utils.ansi_from_hl('MiniIconsBlue', '')
  end

  local buftype = vim.bo[bufnr].buftype
  if buftype == 'terminal' then
    return utils.ansi_from_hl('MiniIconsOrange', '')
  end

  local devicons = require('fzf-lua.devicons')
  devicons.load()
  local icon, color = devicons.get_devicon(path ~= '' and path or 'file')
  if icon == nil or icon == '' then
    return ' '
  end
  if color ~= nil and color ~= '' then
    return utils.ansi_from_rgb(color, icon)
  end
  return icon
end

---@param entry FzfBufferPickerEntry
---@return string
local function make_display_line(entry)
  local fzf_utils = require('fzf-lua.utils')
  local nbsp = fzf_utils.nbsp
  local indicator = vim.bo[entry.bufnr].modified and '' or ' '
  local name = entry.preview_title
  local missing = is_missing_buffer(entry.bufnr, entry.path)
  if missing then
    name = name .. ' [missing]'
  end

  local diagnostics = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.ERROR })
  local has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0
  local warnings = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.WARN })
  local has_warning = warnings[vim.diagnostic.severity.WARN] ~= nil and warnings[vim.diagnostic.severity.WARN] > 0

  local indicator_text = indicator
  if indicator ~= ' ' then
    indicator_text = fzf_utils.ansi_from_hl('DiagnosticWarn', indicator_text)
  end

  local path_text = name
  if missing then
    path_text = fzf_utils.ansi_from_hl('Conceal', path_text)
  elseif has_error then
    path_text = fzf_utils.ansi_from_hl('DiagnosticError', path_text)
  elseif has_warning then
    path_text = fzf_utils.ansi_from_hl('DiagnosticWarn', path_text)
  end

  return string.format('%s%s%s%s%s:%d:%d', indicator_text, nbsp, icon_display(entry.bufnr, entry.path, entry.is_octo), nbsp, path_text, entry.lnum, 1)
end

---@return FzfBufferPickerEntry[]
local function get_entries()
  local entries = {}
  for _, bufnr in ipairs(Buf.get_navigable_buffers(false)) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    local preview_title, is_octo = display_name(bufnr, path)
    local entry = {
      bufnr = bufnr,
      buftype = vim.bo[bufnr].buftype,
      is_octo = is_octo,
      lnum = current_lnum(bufnr),
      path = path,
      preview_title = preview_title,
      line = '',
    }
    entry.line = make_display_line(entry)
    entries[#entries + 1] = entry
  end

  return entries
end

---@param line string
---@return string
local function normalize_line(line)
  local utils = require('fzf-lua.utils')
  return utils.strip_ansi_coloring(line):gsub('%s+$', '')
end

---@param line string
---@return FzfBufferPickerEntry|nil
local function lookup_entry(line)
  local entry = entry_lookup[normalize_line(line)]
  if entry ~= nil and vim.api.nvim_buf_is_valid(entry.bufnr) then
    return entry
  end
  return nil
end

---@param line string
---@return integer|nil, integer
local function parse_line_to_bufnr(line)
  local entry = lookup_entry(line)
  if entry ~= nil then
    return entry.bufnr, entry.lnum
  end

  local path, lnum = line:match('^(.*):(%d+):%d+%s*$')
  if path == nil then
    return nil, 1
  end

  local normalized = path
  if not path:match('^term://') and path ~= '[No Name]' then
    normalized = vim.fn.fnamemodify(path, ':p')
  end

  local bufnr = vim.fn.bufnr(normalized)
  if bufnr == -1 then
    bufnr = vim.fn.bufnr(path)
  end

  if bufnr == -1 then
    return nil, tonumber(lnum) or 1
  end

  return bufnr, tonumber(lnum) or 1
end

---@param src integer
---@param dst integer
local function copy_extmarks(src, dst)
  local extmarks = vim.api.nvim_buf_get_extmarks(src, -1, 0, -1, { details = true })
  for _, extmark in ipairs(extmarks) do
    local _, row, col, details = table.unpack(extmark)
    details.ns_id = nil
    pcall(vim.api.nvim_buf_set_extmark, dst, ns_previewer, row, col, details)
  end
end

local BufferPreviewer = require('fzf-lua.previewer.builtin').buffer_or_file:extend()

---@param entry_str string
---@return table
function BufferPreviewer:parse_entry(entry_str)
  local entry = lookup_entry(entry_str)
  if entry == nil then
    local bufnr, lnum = parse_line_to_bufnr(entry_str)
    if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
      return {}
    end

    local path = vim.api.nvim_buf_get_name(bufnr)
    local preview_title = display_name(bufnr, path)
    return {
      bufnr = bufnr,
      col = 1,
      line = lnum,
      path = path ~= '' and path or nil,
      terminal = vim.bo[bufnr].buftype == 'terminal',
      title = preview_title,
    }
  end

  return {
    bufnr = entry.bufnr,
    col = 1,
    is_octo = entry.is_octo,
    line = entry.lnum,
    path = entry.path ~= '' and entry.path or nil,
    terminal = entry.buftype == 'terminal',
    title = entry.preview_title,
  }
end

---@param tmpbuf integer
---@param entry table
function BufferPreviewer:_populate_loaded_buffer_preview(tmpbuf, entry)
  entry.filetype = vim.bo[entry.bufnr].filetype
  local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
  vim.bo[tmpbuf].expandtab = vim.bo[entry.bufnr].expandtab
  vim.bo[tmpbuf].shiftwidth = vim.bo[entry.bufnr].shiftwidth
  vim.bo[tmpbuf].tabstop = vim.bo[entry.bufnr].tabstop
  vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)

  if entry.is_octo then
    copy_extmarks(entry.bufnr, tmpbuf)
    vim.bo[tmpbuf].filetype = 'markdown'
    vim.bo[tmpbuf].conceallevel = 2
  end

  self:set_preview_buf(tmpbuf, entry.terminal)
  self:preview_buf_post(entry, entry.terminal)
end

---@param selected string[]
local function jump_to_selected(selected)
  local line = selected and selected[1] or nil
  if line == nil then
    return
  end

  local bufnr, lnum = parse_line_to_bufnr(line)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.cmd('buffer ' .. bufnr)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    lnum = math.max(math.min(lnum, line_count), 1)
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
end

---@param selected string[]
local function delete_selected(selected)
  for _, line in ipairs(selected) do
    local bufnr = parse_line_to_bufnr(line)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      local utils = require('fzf-lua.utils')
      local can_delete = not utils.buffer_is_dirty(bufnr, true, false)
      if not can_delete then
        can_delete = vim.api.nvim_buf_call(bufnr, function()
          return utils.save_dialog(bufnr)
        end)
      end
      if can_delete then
        vim.api.nvim_buf_delete(bufnr, { force = false })
      end
    end
  end
end

function M.find_buffers()
  local entries = get_entries()
  if vim.tbl_isempty(entries) then
    vim.notify('No other buffers found', vim.log.levels.ERROR)
    return
  end

  require('fzf-lua').fzf_exec(function(cb)
    entry_lookup = {}
    for _, entry in ipairs(get_entries()) do
      entry_lookup[normalize_line(entry.line)] = entry
      cb(entry.line)
    end
    cb(nil)
  end, {
    prompt = '❯ ',
    __resume_key = 'buffers_custom',
    _type = 'file',
    previewer = {
      _ctor = function()
        return BufferPreviewer
      end,
    },
    file_icons = false,
    no_action_set_cursor = true,
    header = false,
    fzf_opts = {
      ['--multi'] = true,
      ['--tiebreak'] = 'index',
    },
    winopts = {
      title = 'Buffers',
      height = 0.8,
      width = 0.8,
      preview = {
        layout = 'flex',
        flip_columns = 140,
        horizontal = 'right:50%',
        vertical = 'down:45%',
        title = 'Grep Preview',
      },
    },
    actions = {
      ['default'] = jump_to_selected,
      ['ctrl-x'] = { fn = delete_selected, reload = true },
    },
  })
end

return M
