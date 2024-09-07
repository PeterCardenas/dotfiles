local function make_buffer_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {
    path_display = { smart = true },
  }

  local displayer = require('telescope.pickers.entry_display').create({
    separator = ' ',
    items = {
      { width = 4 },
      { width = icon_width },
      { remaining = true },
    },
  })

  local cwd = require('telescope.utils').path_expand(require('utils.file').get_cwd())

  local make_display = function(entry)
    -- modes + icon + 3 spaces + : + lnum
    opts.__prefix = 4 + icon_width + 3 + 1 + #tostring(entry.lnum)
    local display_bufname = require('telescope.utils').transform_path(opts, entry.filename)
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)

    return displayer({
      { entry.indicator, 'TelescopeResultsComment' },
      { icon, hl_group },
      display_bufname .. ':' .. entry.lnum,
    })
  end

  return function(entry)
    local filename = entry.info.name ~= '' and entry.info.name or nil
    local Path = require('plenary.path')
    local bufname = filename and Path:new(filename):normalize(cwd) or '[No Name]'

    local hidden = entry.info.hidden == 1 and 'h' or 'a'
    local readonly = vim.api.nvim_get_option_value('readonly', { buf = entry.bufnr }) and '=' or ' '
    local changed = entry.info.changed == 1 and '+' or ' '
    local indicator = entry.flag .. hidden .. readonly .. changed
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

    return require('telescope.make_entry').set_default_entry_mt({
      value = bufname,
      ordinal = entry.bufnr .. ' : ' .. bufname,
      display = make_display,
      bufnr = entry.bufnr,
      path = filename,
      filename = bufname,
      lnum = lnum,
      indicator = indicator,
    }, opts)
  end
end

local M = {}

function M.find_buffers()
  local bufnrs = vim.tbl_filter(function(bufnr)
    if 1 ~= vim.fn.buflisted(bufnr) then
      return false
    end
    if bufnr == vim.api.nvim_get_current_buf() then
      return false
    end

    return true
  end, vim.api.nvim_list_bufs())

  if not next(bufnrs) then
    vim.notify('No other buffers found', vim.log.levels.ERROR)
    return
  end

  table.sort(bufnrs, function(a, b)
    return vim.fn.getbufinfo(a)[1].lastused > vim.fn.getbufinfo(b)[1].lastused
  end)

  local buffers = {}
  local default_selection_idx = 1
  for _, bufnr in ipairs(bufnrs) do
    local flag = bufnr == vim.fn.bufnr('') and '%' or (bufnr == vim.fn.bufnr('#') and '#' or ' ')

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

    table.insert(buffers, element)
  end

  local max_bufnr = math.max(unpack(bufnrs))
  local opts = { bufnr_width = #tostring(max_bufnr) }

  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Buffers',
      finder = require('telescope.finders').new_table({
        results = buffers,
        entry_maker = make_buffer_entry(),
      }),
      previewer = require('telescope.config').values.grep_previewer(opts),
      sorter = require('telescope.config').values.generic_sorter(opts),
      default_selection_index = default_selection_idx,
      attach_mappings = function(_, map)
        map('i', '<c-x>', function(prompt_bufnr)
          require('telescope.actions').delete_buffer(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
