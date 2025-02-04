local function make_buffer_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {}

  local displayer = require('plugins.telescope.entry_display').make_entry_display({
    separator = ' ',
    items = {
      { width = 1 },
      { width = icon_width },
      { remaining = true },
    },
  })

  local cwd = require('telescope.utils').path_expand(require('utils.file').get_cwd())

  ---@class BufferPickerEntry
  ---@field bufnr number
  ---@field filename string
  ---@field lnum number
  ---@field indicator string

  ---@param entry BufferPickerEntry
  ---@param picker Picker
  local make_display = function(entry, picker)
    -- icon + : + lnum
    opts.__prefix = icon_width + 1 + #tostring(entry.lnum)
    local display_bufname = require('telescope.utils').transform_path(opts, entry.filename)
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)
    local diagnostics = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.ERROR })
    local has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0
    local Path = require('plenary.path')
    local full_path = Path:new(entry.filename):expand()
    local buftype = vim.bo[entry.bufnr].buftype
    local is_removed = buftype ~= 'acwrite' and buftype ~= 'nofile' and vim.fn.filereadable(full_path) == 0

    return displayer({
      { entry.indicator, 'DiagnosticWarn' },
      { icon, hl_group },
      { path = display_bufname, lnum = entry.lnum, has_error = has_error, is_removed = is_removed },
    }, picker)
  end

  ---@class BufferEntry
  ---@field bufnr number
  ---@field info vim.fn.getbufinfo.ret.item

  ---@param entry BufferEntry
  return function(entry)
    local filename = entry.info.name ~= '' and entry.info.name or nil
    local Path = require('plenary.path')
    local bufname = filename and Path:new(filename):normalize(cwd) or '[No Name]'

    local changed = entry.info.changed == 1 and '' or ' '
    local indicator = changed
    local lnum = 1

    -- account for potentially stale lnum as getbufinfo might not be updated or from resuming buffers picker
    if entry.info.lnum ~= 0 then
      -- but make sure the buffer is loaded, otherwise line_count is 0
      if vim.api.nvim_buf_is_loaded(entry.bufnr) then
        local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
        lnum = math.max(math.min(entry.info.lnum, line_count), 1)
      else
        lnum = entry.info.lnum
      end
    end

    ---@type BufferPickerEntry
    local buffer_picker_entry = {
      value = bufname,
      ordinal = entry.bufnr .. ' : ' .. bufname,
      display = make_display,
      bufnr = entry.bufnr,
      path = filename,
      filename = bufname,
      lnum = lnum,
      indicator = indicator,
    }
    return require('telescope.make_entry').set_default_entry_mt(buffer_picker_entry, opts)
  end
end

local M = {}

function M.find_buffers()
  local bufnrs = require('utils.buf').get_navigable_buffers(false)
  if not next(bufnrs) then
    vim.notify('No other buffers found', vim.log.levels.ERROR)
    return
  end

  ---@type BufferEntry[]
  local buffers = {}
  for _, bufnr in ipairs(bufnrs) do
    ---@type BufferEntry
    local element = {
      bufnr = bufnr,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

    table.insert(buffers, element)
  end

  local opts = {}

  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Buffers',
      results_title = false,
      layout_config = {
        prompt_position = 'top',
        width = 0.8,
        preview_width = 0.5,
      },
      finder = require('telescope.finders').new_table({
        results = buffers,
        entry_maker = make_buffer_entry(),
      }),
      -- TODO: Use octo previewer for octo buffers
      previewer = require('telescope.config').values.grep_previewer(opts),
      sorter = require('telescope.config').values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr_, map)
        require('plugins.telescope.entry_display').create_autocommands(prompt_bufnr_)
        map({ 'n', 'i' }, '<c-x>', function(prompt_bufnr)
          require('telescope.actions').delete_buffer(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
