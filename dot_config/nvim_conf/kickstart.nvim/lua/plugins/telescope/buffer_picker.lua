local M = {}

---@class EntryDisplayConfigItem
---@field width? number
---@field right_justify? boolean
---@field remaining? boolean
---@class EntryDisplayConfig
---@field items EntryDisplayConfigItem[]
---@field separator string
---@alias PathEntryDisplayItem { path: string, lnum?: number, has_error?: boolean, has_warning?: boolean }
---@alias EntryDisplayItem string | { [1]: string, [2]: string } | PathEntryDisplayItem

---@param configuration EntryDisplayConfig
---@return fun(self: EntryDisplayItem[], picker: Picker): string, table
function M.make_entry_display(configuration)
  local resolve = require('telescope.config.resolve')
  local strings = require('plenary.strings')
  local generator = {}
  local acc_width = 0
  for index, v in ipairs(configuration.items) do
    if v.width then
      acc_width = acc_width + v.width
      local justify = v.right_justify
      local width
      table.insert(generator, function(item, picker)
        if width == nil then
          local results_win = picker.results_border.content_win_id
          local s = {}
          s[1] = vim.api.nvim_win_get_width(results_win) - #picker.selection_caret
          s[2] = vim.api.nvim_win_get_height(results_win)
          width = resolve.resolve_width(v.width)(nil, s[1], s[2])
        end
        if type(item) == 'table' then
          return strings.align_str(strings.truncate(item[1], width), width, justify), item[2]
        else
          return strings.align_str(strings.truncate(item, width), width, justify)
        end
      end)
    else
      if index ~= #configuration.items then
        vim.notify('Only the last item can have undefined width', vim.log.levels.ERROR)
      elseif v.remaining ~= true then
        vim.notify('Should specify that the last item is taking the remaining space', vim.log.levels.ERROR)
      end
      ---@param item EntryDisplayItem
      ---@param picker Picker
      table.insert(generator, function(item, picker)
        if type(item) == 'table' then
          if item.path ~= nil then
            local results_win = picker.results_border.content_win_id
            local results_width = vim.api.nvim_win_get_width(results_win)
            local lnum_str = item.lnum and tostring(item.lnum) or ''
            local path_target_width = results_width
              - acc_width
              - vim.fn.strdisplaywidth(configuration.separator) * (#configuration.items + 1)
              - vim.fn.strdisplaywidth(lnum_str)
            if item.lnum ~= nil then
              path_target_width = path_target_width - 1
            end
            local path_current_width = vim.fn.strdisplaywidth(item.path)
            if path_current_width <= path_target_width then
              if item.lnum ~= nil then
                return item.path .. ':' .. item.lnum
              end
              return item.path
            end
            local path_parts = vim.split(item.path, '/')
            local path_index = 2
            while path_index <= #path_parts and path_current_width > path_target_width do
              local path_part = path_parts[path_index]
              local length_to_truncate = vim.fn.strdisplaywidth(path_part) - (path_current_width - path_target_width)
              path_parts[path_index] = vim.fn.strcharpart(path_part, 0, math.max(1, length_to_truncate - 1)) .. '…'
              path_current_width = path_current_width - vim.fn.strdisplaywidth(path_part) + vim.fn.strdisplaywidth(path_parts[path_index])
              path_index = path_index + 1
            end
            local truncated_path = table.concat(path_parts, '/')
            if item.lnum ~= nil then
              truncated_path = truncated_path .. ':' .. item.lnum
            end
            if item.has_error then
              return truncated_path, 'DiagnosticError'
            elseif item.has_warning then
              return truncated_path, 'DiagnosticWarn'
            end
            return truncated_path
          end
          return item[1], item[2]
        else
          return item
        end
      end)
    end
  end

  return function(self, picker)
    local results = {}
    local highlights = {}
    for i = 1, #generator do
      if self[i] ~= nil then
        local str, hl = generator[i](self[i], picker)
        if hl then
          local hl_start = 0
          for j = 1, (i - 1) do
            hl_start = hl_start + #results[j] + #configuration.separator
          end
          local hl_end = hl_start + #str:gsub('%s*$', '')

          if type(hl) == 'function' then
            for _, hl_res in ipairs(hl()) do
              table.insert(highlights, { { hl_res[1][1] + hl_start, hl_res[1][2] + hl_start }, hl_res[2] })
            end
          else
            table.insert(highlights, { { hl_start, hl_end }, hl })
          end
        end

        table.insert(results, str)
      end
    end

    local final_str = table.concat(results, configuration.separator)

    return final_str, highlights
  end
end

local function make_buffer_entry()
  local icon_width = require('plenary.strings').strdisplaywidth((require('telescope.utils').get_devicons('fname')))
  local opts = {}

  local displayer = M.make_entry_display({
    separator = ' ',
    items = {
      { width = 1 },
      { width = icon_width },
      { remaining = true },
    },
  })

  local cwd = require('telescope.utils').path_expand(require('utils.file').get_cwd())

  local make_display = function(entry, picker)
    -- icon + : + lnum
    opts.__prefix = icon_width + 1 + #tostring(entry.lnum)
    local display_bufname = require('telescope.utils').transform_path(opts, entry.filename)
    local icon, hl_group = require('telescope.utils').get_devicons(entry.filename)
    local diagnostics = vim.diagnostic.count(entry.bufnr, { severity = vim.diagnostic.severity.ERROR })
    local has_error = diagnostics[vim.diagnostic.severity.ERROR] ~= nil and diagnostics[vim.diagnostic.severity.ERROR] > 0

    return displayer({
      { entry.indicator, 'DiagnosticWarn' },
      { icon, hl_group },
      { path = display_bufname, lnum = entry.lnum, has_error = has_error },
    }, picker)
  end

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
  for _, bufnr in ipairs(bufnrs) do
    local flag = bufnr == vim.fn.bufnr('') and '%' or (bufnr == vim.fn.bufnr('#') and '#' or ' ')

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

    table.insert(buffers, element)
  end

  local resize_augroup = vim.api.nvim_create_augroup('BufferPickerResize', { clear = true })
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
      previewer = require('telescope.config').values.grep_previewer(opts),
      sorter = require('telescope.config').values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr_, map)
        local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr_)
        local results_win = picker.results_border.content_win_id
        vim.api.nvim_create_autocmd('VimResized', {
          group = resize_augroup,
          callback = function()
            picker:refresh()
          end,
        })
        vim.api.nvim_create_autocmd('WinClosed', {
          group = resize_augroup,
          callback = function(args)
            local closed_win = tonumber(args.match, 10)
            if closed_win ~= results_win then
              return
            end
            vim.api.nvim_del_augroup_by_id(resize_augroup)
          end,
        })
        map({ 'n', 'i' }, '<c-x>', function(prompt_bufnr)
          require('telescope.actions').delete_buffer(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
