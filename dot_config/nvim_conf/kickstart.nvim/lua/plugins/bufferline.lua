---Delete a buffer given an id.
---@param bufnum number
local function close_buffer(bufnum)
  require('bufdelete').bufdelete(bufnum, false)
end

local nmap = require('utils.keymap').nmap

local function add_keymaps()
  nmap('Close buffer', 'cc', function()
    local current_bufnr = vim.api.nvim_get_current_buf()
    close_buffer(current_bufnr)
  end)

  nmap('Close all other buffers', 'co', function()
    require('bufferline').close_others()
  end)

  nmap('Close all buffers to the right', 'cl', function()
    require('bufferline').close_in_direction('right')
  end)

  nmap('Close all buffers to the left', 'ch', function()
    require('bufferline').close_in_direction('left')
  end)

  vim.keymap.set('n', '<S-l>', function()
    local navigation_offset = vim.v.count > 0 and vim.v.count or 1
    require('bufferline').cycle(navigation_offset)
  end, { desc = 'Next buffer' })

  vim.keymap.set('n', '<S-h>', function()
    local navigation_offset = -(vim.v.count > 0 and vim.v.count or 1)
    require('bufferline').cycle(navigation_offset)
  end, { desc = 'Previous buffer' })

  nmap('Move buffer tab right', 'rl', function()
    local move_offset = vim.v.count > 0 and vim.v.count or 1
    require('bufferline').move(move_offset)
  end)

  nmap('Move buffer tab left', 'rh', function()
    local move_offset = -(vim.v.count > 0 and vim.v.count or 1)
    require('bufferline').move(move_offset)
  end)
end

if not require('utils.config').USE_HEIRLINE and require('utils.config').USE_TABLINE then
  add_keymaps()
end

---@type LazyPluginSpec
return {
  'akinsho/bufferline.nvim',
  cond = function()
    return not require('utils.config').USE_HEIRLINE and require('utils.config').USE_TABLINE
  end,
  config = function()
    require('bufferline').setup({
      options = {
        close_command = close_buffer,
        right_mouse_command = nil,
        middle_mouse_command = close_buffer,
        diagnostics = 'nvim_lsp',
        diagnostics_indicator = function(count, level)
          local icon = level:match('error') and ' ' or ' '
          return ' ' .. icon .. count
        end,
        offsets = {
          {
            filetype = 'NvimTree',
            text = 'File Explorer',
            text_align = 'center',
            separator = false,
          },
        },
        ---@type fun(buf_a: bufferline.Buffer, buf_b: bufferline.Buffer): boolean
        sort_by = function(buf_a, buf_b)
          local modified_weight_a = buf_a.modified and 1 or 0
          local modified_weight_b = buf_b.modified and 1 or 0
          -- Most recently used buffer first (leftmost)
          return modified_weight_a > modified_weight_b
        end,
      },
    })
  end,
}
