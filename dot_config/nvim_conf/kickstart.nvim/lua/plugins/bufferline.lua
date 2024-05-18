---Delete a buffer given an id.
---@param bufnum number
local function close_buffer(bufnum)
  require('bufdelete').bufdelete(bufnum, false)
end

local function add_keymaps()
  vim.keymap.set('n', '<leader>cc', function()
    local current_bufnr = vim.api.nvim_get_current_buf()
    close_buffer(current_bufnr)
  end, { desc = 'Close buffer' })

  vim.keymap.set('n', '<leader>co', function()
    require('bufferline').close_others()
  end, { desc = 'Close all other buffers' })

  vim.keymap.set('n', '<leader>cl', function()
    require('bufferline').close_in_direction('right')
  end, { desc = 'Close all buffers to the right' })

  vim.keymap.set('n', '<leader>ch', function()
    require('bufferline').close_in_direction('left')
  end, { desc = 'Close all buffers to the left' })

  vim.keymap.set('n', '<S-l>', function()
    local navigation_offset = vim.v.count > 0 and vim.v.count or 1
    require('bufferline').cycle(navigation_offset)
  end, { desc = 'Next buffer' })

  vim.keymap.set('n', '<S-h>', function()
    local navigation_offset = -(vim.v.count > 0 and vim.v.count or 1)
    require('bufferline').cycle(navigation_offset)
  end, { desc = 'Previous buffer' })

  vim.keymap.set('n', '<leader>rl', function()
    local move_offset = vim.v.count > 0 and vim.v.count or 1
    require('bufferline').move(move_offset)
  end, { desc = 'Move buffer tab right' })

  vim.keymap.set('n', '<leader>rh', function()
    local move_offset = -(vim.v.count > 0 and vim.v.count or 1)
    require('bufferline').move(move_offset)
  end, { desc = 'Move buffer tab left' })
end

if not require('utils.config').USE_HEIRLINE then
  add_keymaps()
end

---@type LazyPluginSpec
return {
  'akinsho/bufferline.nvim',
  version = '73540cb',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  cond = function()
    return not require('utils.config').USE_HEIRLINE
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
