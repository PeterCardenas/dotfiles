local M = {}

---@return fun(filename: string): table
function M.make_files_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {}

  local displayer = require('plugins.telescope.entry_display').make_entry_display({
    separator = ' ',
    items = {
      { width = icon_width },
      { remaining = true },
    },
  })
  local bufnrs = vim.api.nvim_list_bufs()
  local fname_to_bufnr = {}
  for _, bufnr in ipairs(bufnrs) do
    local fname = vim.api.nvim_buf_get_name(bufnr)
    fname_to_bufnr[fname] = bufnr
  end

  local cwd = require('utils.file').get_cwd()

  ---@class FilePickerEntry
  ---@field filename string

  ---@param entry FilePickerEntry
  ---@param picker Picker
  local make_display = function(entry, picker)
    opts.__prefix = icon_width
    local display_bufname = require('telescope.utils').transform_path(opts, entry.filename)
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)
    local has_error = false
    local has_warning = false
    local maybe_bufnr = fname_to_bufnr[cwd .. '/' .. entry.filename]
    if maybe_bufnr ~= nil then
      local diagnostics = vim.diagnostic.count(maybe_bufnr, { severity = vim.diagnostic.severity.ERROR })
      has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0
      has_warning = vim.api.nvim_get_option_value('modified', { buf = maybe_bufnr })
    end

    return displayer({
      { icon, hl_group },
      { path = display_bufname, has_error = has_error, has_warning = has_warning },
    }, picker)
  end

  ---@param filename string
  return function(filename)
    ---@type FilePickerEntry
    local entry = {
      value = filename,
      ordinal = filename,
      display = make_display,
      filename = filename,
    }
    return require('telescope.make_entry').set_default_entry_mt(entry, opts)
  end
end

---@class FindFilesOpts
---@field show_ignore boolean

---@param find_opts FindFilesOpts
function M.find_files(find_opts)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local command = { 'rg', '--files', '--color', 'never', '--hidden' }
  if find_opts.show_ignore then
    table.insert(command, '--no-ignore')
  end
  local opts = {
    entry_maker = M.make_files_entry(),
  }

  pickers
    .new(opts, {
      prompt_title = 'Find Files',
      finder = finders.new_oneshot_job(command, opts),
      previewer = conf.file_previewer(opts),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        require('plugins.telescope.entry_display').create_autocommands(prompt_bufnr)

        return true
      end,
    })
    :find()
end

return M
