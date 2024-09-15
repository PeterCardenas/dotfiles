local function make_files_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {}

  local displayer = require('plugins.telescope.buffer_picker').make_entry_display({
    separator = ' ',
    items = {
      { width = icon_width },
      { remaining = true },
    },
  })

  local make_display = function(entry, picker)
    opts.__prefix = icon_width
    local display_bufname = require('telescope.utils').transform_path(opts, entry.filename)
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)
    -- local diagnostics = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.ERROR })
    -- local has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0

    return displayer({
      { icon, hl_group },
      { path = display_bufname },
    }, picker)
  end

  ---@param filename string
  return function(filename)
    return require('telescope.make_entry').set_default_entry_mt({
      value = filename,
      ordinal = filename,
      display = make_display,
      filename = filename,
    }, opts)
  end
end

local M = {}

---@class FindFilesOpts
---@field show_ignore boolean

---@param find_opts FindFilesOpts
function M.find_files(find_opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local entry_maker = require('telescope.make_entry')
  local command = { 'rg', '--files', '--color', 'never', '--hidden' }
  if find_opts.show_ignore then
    table.insert(command, '--no-ignore')
  end
  local opts = {
    entry_maker = make_files_entry(),
  }

  pickers
    .new(opts, {
      prompt_title = 'Find Files',
      finder = finders.new_oneshot_job(command, opts),
      previewer = conf.file_previewer(opts),
      sorter = conf.file_sorter(opts),
    })
    :find()
end

return M
