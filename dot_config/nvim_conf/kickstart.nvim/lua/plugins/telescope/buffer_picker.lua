local File = require('utils.file')
local EntryDisplay = require('plugins.telescope.entry_display')
local Buf = require('utils.buf')

local ns_previewer = vim.api.nvim_create_namespace('buffer_picker_previewer')

local function make_buffer_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {}

  local displayer = EntryDisplay.make_entry_display({
    separator = ' ',
    items = {
      { width = 1 },
      { width = icon_width },
      { remaining = true },
    },
  })

  local cwd = require('telescope.utils').path_expand(File.get_cwd())

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
    ---@type string, string
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)
    local diagnostics = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.ERROR })
    local has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0
    local Path = require('plenary.path')
    ---@type string
    local full_path = Path:new(entry.filename):expand()
    if octo_buffers and octo_buffers[entry.bufnr] then
      local octo_buf = octo_buffers[entry.bufnr]
      display_bufname = octo_buf.titleMetadata.body or ''
      icon = ''
    end
    local buftype = vim.bo[entry.bufnr].buftype
    if buftype == 'terminal' then
      icon = ''
      hl_group = 'MiniIconsOrange'
    end
    local is_removed = buftype ~= 'terminal' and buftype ~= 'acwrite' and buftype ~= 'nofile' and vim.fn.filereadable(full_path) == 0

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
    local octo_title = ''
    if octo_buffers and octo_buffers[entry.bufnr] then
      local octo_buf = octo_buffers[entry.bufnr]
      octo_title = octo_buf.titleMetadata.body or ''
    end

    ---@type BufferPickerEntry
    local buffer_picker_entry = {
      value = bufname,
      ordinal = entry.bufnr .. ' : ' .. bufname .. octo_title,
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
  local bufnrs = Buf.get_navigable_buffers(false)
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

    buffers[#buffers + 1] = element
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
      previewer = {
        (function(previewer_opts)
          previewer_opts = previewer_opts or {}
          local cwd = previewer_opts.cwd or vim.loop.cwd()

          local function jump_to_line(self, bufnr, entry)
            if entry.lnum and entry.lnum > 0 then
              ---@type number, number
              local lnum, lnend = entry.lnum - 1, (entry.lnend or entry.lnum) - 1

              local col, colend = 0, -1
              -- Both col delimiters should be provided for them to take effect.
              -- This is to ensure that column range highlighting was opted in, as `col`
              -- is already used to determine the buffer jump position elsewhere.
              if entry.col and entry.colend then
                ---@type number, number
                col, colend = entry.col - 1, entry.colend - 1
              end

              for i = lnum, lnend do
                pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_previewer, 'TelescopePreviewLine', i, i == lnum and col or 0, i == lnend and colend or -1)
              end

              local middle_ln = math.floor(lnum + (lnend - lnum) / 2)
              pcall(vim.api.nvim_win_set_cursor, self.state.winid, { middle_ln + 1, 0 })
              if bufnr ~= nil then
                vim.api.nvim_buf_call(bufnr, function()
                  vim.cmd('norm! zz')
                end)
              end
            end
          end

          local from_entry = require('telescope.from_entry')
          return require('telescope.previewers').new_buffer_previewer({
            title = 'Grep Preview',
            dyn_title = function(_, entry)
              local Path = require('plenary.path')
              return Path:new(from_entry.path(entry, false, false)):normalize(cwd)
            end,

            get_buffer_by_name = function(_, entry)
              return from_entry.path(entry, false, false)
            end,

            define_preview = function(self, entry)
              -- builtin.buffers: bypass path validation for terminal buffers that don't have appropriate path
              local has_buftype = entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) and vim.api.nvim_buf_get_option(entry.bufnr, 'buftype') ~= '' or false
              ---@type string
              local p
              if not has_buftype then
                p = from_entry.path(entry, true, false) --[[@as string]]
                if p == nil or p == '' then
                  return
                end
              end

              -- Workaround for unnamed buffer when using builtin.buffer
              if entry.bufnr and (p == '[No Name]' or has_buftype or octo_buffers[entry.bufnr]) then
                local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                -- schedule so that the lines are actually there and can be jumped onto when we call jump_to_line
                vim.schedule(function()
                  if octo_buffers[entry.bufnr] then
                    local extmarks = vim.api.nvim_buf_get_extmarks(entry.bufnr, -1, 0, -1, { details = true })
                    for _, extmark in ipairs(extmarks) do
                      local _, row, col, details = unpack(extmark)
                      details.ns_id = nil
                      vim.api.nvim_buf_set_extmark(self.state.bufnr, ns_previewer, row, col, details)
                    end
                    vim.bo[self.state.bufnr].filetype = 'markdown'
                    vim.api.nvim_buf_set_option(self.state.bufnr, 'conceallevel', 2)
                  end
                  jump_to_line(self, self.state.bufnr, entry)
                end)
              else
                require('telescope.config').values.buffer_previewer_maker(p, self.state.bufnr, {
                  bufname = self.state.bufname,
                  winid = self.state.winid,
                  preview = previewer_opts.preview,
                  callback = function(bufnr)
                    jump_to_line(self, bufnr, entry)
                  end,
                  file_encoding = previewer_opts.file_encoding,
                })
              end
            end,
          })
        end)(),
      },
      sorter = require('telescope.config').values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr_, map)
        EntryDisplay.create_autocommands(prompt_bufnr_)
        map({ 'n', 'i' }, '<c-x>', function(prompt_bufnr)
          require('telescope.actions').delete_buffer(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
