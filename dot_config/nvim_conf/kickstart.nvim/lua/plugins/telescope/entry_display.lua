local M = {}

---@class EntryDisplayConfigItem
---@field width? number
---@field right_justify? boolean
---@field remaining? boolean
---@class EntryDisplayConfig
---@field items EntryDisplayConfigItem[]
---@field separator string
---@alias PathEntryDisplayItem { path: string, lnum?: number, has_error?: boolean, has_warning?: boolean, is_removed?: boolean}
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
        if type(item) == 'string' then
          return item
        end
        if item.path == nil then
          return item[1], item[2]
        end
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
        local path_parts = vim.split(item.path, '/')
        local path_index = 2
        while path_index <= #path_parts and path_current_width > path_target_width do
          local path_part = path_parts[path_index]
          local length_to_truncate = vim.fn.strdisplaywidth(path_part) - (path_current_width - path_target_width)
          path_parts[path_index] = vim.fn.strcharpart(path_part, 0, math.max(1, length_to_truncate - 1)) .. '…'
          path_current_width = path_current_width - vim.fn.strdisplaywidth(path_part) + vim.fn.strdisplaywidth(path_parts[path_index])
          path_index = path_index + 1
        end
        local final_path = table.concat(path_parts, '/')
        if item.lnum ~= nil then
          final_path = final_path .. ':' .. item.lnum
        end
        if item.is_removed then
          return final_path, 'Conceal'
        elseif item.has_error then
          return final_path, 'DiagnosticError'
        elseif item.has_warning then
          return final_path, 'DiagnosticWarn'
        end
        return final_path
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

---@param prompt_bufnr number
function M.create_autocommands(prompt_bufnr)
  local resize_augroup = vim.api.nvim_create_augroup('BufferPickerResize', { clear = true })
  local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
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
end

return M
