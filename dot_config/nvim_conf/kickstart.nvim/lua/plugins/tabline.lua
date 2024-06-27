-- Autocmds to make the internal buffer list state in sync with the actual buffers.
local function is_valid_buffer(bufnr)
  if not bufnr or bufnr < 1 then
    return false
  end
  return vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_valid(bufnr)
end

local function add_keymaps()
  -- Manage Buffers
  vim.keymap.set({ 'v', 'n' }, '<leader>C', function()
    local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
    require('bufdelete').bufdelete(bufs, true)
  end, { desc = 'Close all buffers' })
  ---@param navigation_offset integer
  local function nav_buf(navigation_offset)
    local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
    local current_bufnr = vim.api.nvim_get_current_buf()
    for i, bufnr in ipairs(bufs) do
      if bufnr == current_bufnr then
        local new_bufnr_idx = (i + navigation_offset - 1) % #bufs + 1
        vim.cmd.b(bufs[new_bufnr_idx])
        break
      end
    end
  end
  ---@param bufnr integer
  local function force_close_buf(bufnr)
    vim.schedule(function()
      require('bufdelete').bufdelete(bufnr, true)
    end)
  end
  local function close_buf()
    local current_bufnr = vim.api.nvim_get_current_buf()
    local is_modified = vim.api.nvim_get_option_value('modified', { buf = current_bufnr })
    if is_modified then
      local choice = vim.fn.input('Buffer modified. Save? (y/n): ')
      if choice == 'y' then
        vim.cmd.w()
      elseif choice ~= 'n' then
        vim.notify('Buffer close failed.', vim.log.levels.WARN)
        return
      end
    end
    local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
    if #bufs == 1 then
      force_close_buf(current_bufnr)
      return
    end
    local jumplist_result = vim.fn.getjumplist()
    if not jumplist_result then
      force_close_buf(current_bufnr)
      return
    end
    local jumplist, current_jumplist_index = jumplist_result[1], jumplist_result[2]
    local target_jumplist_index = current_jumplist_index
    local target_bufnr = jumplist[target_jumplist_index].bufnr
    while target_jumplist_index > 1 and (current_bufnr == target_bufnr or not vim.tbl_contains(bufs, target_bufnr)) do
      target_jumplist_index = target_jumplist_index - 1
      target_bufnr = jumplist[target_jumplist_index].bufnr
    end
    vim.cmd.b(target_bufnr)
    force_close_buf(current_bufnr)
  end
  ---@param move_offset integer
  local function move_buf(move_offset)
    if move_offset == 0 then
      return
    end -- if n = 0 then no shifts are needed
    local bufs = vim.api.nvim_tabpage_get_var(0, 'bufs')
    for i, bufnr in ipairs(bufs) do -- loop to find current buffer
      if bufnr == vim.api.nvim_get_current_buf() then -- found index of current buffer
        for _ = 0, (move_offset % #bufs) - 1 do -- calculate number of right shifts
          local new_i = i + 1 -- get next i
          if i == #bufs then -- if at end, cycle to beginning
            new_i = 1 -- next i is actually 1 if at the end
            local val = bufs[i] -- save value
            table.remove(bufs, i) -- remove from end
            table.insert(bufs, new_i, val) -- insert at beginning
          else -- if not at the end,then just do an in place swap
            bufs[i], bufs[new_i] = bufs[new_i], bufs[i]
          end
          i = new_i -- iterate i to next value
        end
        break
      end
    end
    -- set buffers
    vim.api.nvim_tabpage_set_var(0, 'bufs', bufs)
    -- redraw tabline
    vim.cmd.redrawtabline()
  end
  vim.keymap.set('n', '<leader>c', close_buf, { desc = 'Close buffer' })
  vim.keymap.set('n', '<S-l>', function()
    local navigation_offset = vim.v.count > 0 and vim.v.count or 1
    nav_buf(navigation_offset)
  end, { desc = 'Next buffer' })
  vim.keymap.set('n', '<S-h>', function()
    local navigation_offset = -(vim.v.count > 0 and vim.v.count or 1)
    nav_buf(navigation_offset)
  end, { desc = 'Previous buffer' })
  vim.keymap.set('n', '<leader>rl', function()
    move_buf(vim.v.count > 0 and vim.v.count or 1)
  end, { desc = 'Move buffer tab right' })
  vim.keymap.set('n', '<leader>rh', function()
    move_buf(-(vim.v.count > 0 and vim.v.count or 1))
  end, { desc = 'Move buffer tab left' })
end

local function register_autocmds()
  local bufferline_group = vim.api.nvim_create_augroup('bufferline', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufAdd', 'BufEnter' }, {
    desc = 'Update buffers when adding new buffers',
    group = bufferline_group,
    callback = function(args)
      local success, bufs = pcall(function()
        return vim.api.nvim_tabpage_get_var(0, 'bufs')
      end)
      if not success then
        bufs = {}
      end
      if not vim.tbl_contains(bufs, args.buf) then
        local current_buf = vim.api.nvim_get_current_buf()
        if vim.g.session_loaded and current_buf ~= args.buf then
          for buf_index, bufnr in ipairs(bufs) do
            if bufnr == current_buf then
              table.insert(bufs, buf_index + 1, args.buf)
              break
            end
          end
        else
          table.insert(bufs, args.buf)
        end
      end
      bufs = vim.tbl_filter(is_valid_buffer, bufs)
      vim.api.nvim_tabpage_set_var(0, 'bufs', bufs)
    end,
  })
  vim.api.nvim_create_autocmd({ 'User' }, {
    pattern = 'SessionLoadPost',
    group = vim.api.nvim_create_augroup('session_loaded_post', { clear = true }),
    callback = function()
      vim.g.session_loaded = true
    end,
  })
  vim.api.nvim_create_autocmd('BufDelete', {
    desc = 'Update buffers when deleting buffers',
    group = bufferline_group,
    callback = function(args)
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local success, bufs = pcall(function()
          return vim.api.nvim_tabpage_get_var(0, 'bufs')
        end)
        if not success then
          bufs = {}
        end
        if bufs then
          for i, bufnr in ipairs(bufs) do
            if bufnr == args.buf then
              table.remove(bufs, i)
              break
            end
          end
        end
        bufs = vim.tbl_filter(is_valid_buffer, bufs)
        vim.api.nvim_tabpage_set_var(tab, 'bufs', bufs)
      end
      vim.cmd.redrawtabline()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    desc = 'Quit AstroNvim if more than one window is open and only sidebar windows are list',
    group = vim.api.nvim_create_augroup('auto_quit', { clear = true }),
    callback = function()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      if #wins <= 1 then
        return
      end
      local sidebar_fts = { ['NvimTree'] = true }
      for _, winid in ipairs(wins) do
        if vim.api.nvim_win_is_valid(winid) then
          local bufnr = vim.api.nvim_win_get_buf(winid)
          local filetype = vim.api.nvim_get_option_value('filetype', { buf = bufnr })
          -- If any visible windows are not sidebars, early return
          if not sidebar_fts[filetype] then
            return
            -- If the visible window is a sidebar
          else
            -- only count filetypes once, so remove a found sidebar from the detection
            sidebar_fts[filetype] = nil
          end
        end
      end
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd.tabclose()
      else
        vim.cmd.qall()
      end
    end,
  })
end

if require('utils.config').USE_HEIRLINE and require('utils.config').USE_TABLINE then
  -- TODO: wtf is this?
  vim.cmd([[au FileType * if index(['wipe', 'delete'], &bufhidden) >= 0 | set nobuflisted | endif]])

  register_autocmds()
  add_keymaps()
end

---@type LazyPluginSpec
return {
  -- Tabline (Also has a winbar and statusline that are not currently used)
  'rebelot/heirline.nvim',
  cond = function()
    return require('utils.config').USE_HEIRLINE and require('utils.config').USE_TABLINE
  end,
  config = function()
    -- [[ Configure heirline ]]
    -- See `:help heirline`
    local heirline_utils = require('heirline.utils')
    local heirline_conditions = require('heirline.conditions')

    -- we redefine the filename component, as we probably only want the tail and not the relative path
    local TablineFileName = {
      provider = function(self)
        -- self.filename will be defined later, just keep looking at the example!
        local filename = self.filename
        filename = filename == '' and '[No Name]' or vim.fn.fnamemodify(filename, ':t')
        return filename
      end,
      hl = function(self)
        return { bold = self.is_active or self.is_visible, italic = true }
      end,
    }

    -- this looks exactly like the FileFlags component that we saw in
    -- #crash-course-part-ii-filename-and-friends, but we are indexing the bufnr explicitly
    -- also, we are adding a nice icon for terminal buffers.
    local TablineFileFlags = {
      {
        condition = function(self)
          return vim.api.nvim_get_option_value('modified', { buf = self.bufnr })
        end,
        provider = '[+]',
        hl = { fg = 'green' },
      },
      {
        condition = function(self)
          return not vim.api.nvim_get_option_value('modifiable', { buf = self.bufnr }) or vim.api.nvim_get_option_value('readonly', { buf = self.bufnr })
        end,
        provider = function(self)
          if vim.api.nvim_get_option_value('buftype', { buf = self.bufnr }) == 'terminal' then
            return '  '
          else
            return ''
          end
        end,
        hl = { fg = 'orange' },
      },
    }

    local FileIcon = {
      init = function(self)
        local filepath = self.filename
        local filename = vim.fn.fnamemodify(filepath, ':t')
        local extension = vim.fn.fnamemodify(filename, ':e')
        self.icon, self.icon_color = require('nvim-web-devicons').get_icon_color(filename, extension, { default = true })
        if self.icon == require('nvim-web-devicons').get_default_icon().icon then
          local filetype = vim.api.nvim_get_option_value('filetype', { buf = self.bufnr })
          self.icon, self.icon_color = require('nvim-web-devicons').get_icon_color_by_filetype(filetype, { default = true })
        end
      end,
      provider = function(self)
        return self.icon and (self.icon .. ' ')
      end,
      hl = function(self)
        return { fg = self.icon_color }
      end,
    }

    -- Here the filename block finally comes together
    local TablineFileNameBlock = {
      init = function(self)
        self.filename = vim.api.nvim_buf_get_name(self.bufnr)
      end,
      hl = function(self)
        if self.is_active then
          return 'TabLineSel'
          -- why not?
          -- elseif not vim.api.nvim_buf_is_loaded(self.bufnr) then
          --     return { fg = "gray" }
        else
          return 'TabLine'
        end
      end,
      on_click = {
        callback = function(_, minwid, _, button)
          if button == 'm' then -- close on mouse middle click
            vim.schedule(function()
              require('bufdelete').bufdelete(minwid, false)
            end)
          else
            vim.api.nvim_win_set_buf(0, minwid)
          end
        end,
        minwid = function(self)
          return self.bufnr
        end,
        name = 'heirline_tabline_buffer_callback',
      },
      FileIcon, -- turns out the version defined in #crash-course-part-ii-filename-and-friends can be reutilized as is here!
      TablineFileName,
      TablineFileFlags,
    }

    -- a nice "x" button to close the buffer
    local TablineCloseButton = {
      condition = function(self)
        return not vim.api.nvim_get_option_value('modified', { buf = self.bufnr })
      end,
      { provider = ' ' },
      {
        provider = '󰖭',
        hl = function(self)
          if self.is_active then
            return 'TabLineClose'
          else
            return 'TabLine'
          end
        end,
        on_click = {
          callback = function(_, minwid)
            vim.schedule(function()
              require('bufdelete').bufdelete(minwid, false)
              vim.cmd.redrawtabline()
            end)
          end,
          minwid = function(self)
            return self.bufnr
          end,
          name = 'heirline_tabline_close_buffer_callback',
        },
      },
    }

    local TablineBufferBlock = heirline_utils.surround({ '', '' }, function(self)
      if self.is_active then
        return heirline_utils.get_highlight('TabLineSel').bg
      else
        return heirline_utils.get_highlight('TabLine').bg
      end
    end, { { provider = ' ' }, TablineFileNameBlock, TablineCloseButton, { provider = ' ' } })

    local BufferLine = heirline_utils.make_buflist(
      TablineBufferBlock,
      { provider = '  ', hl = { fg = 'gray' } }, -- left truncation, optional (defaults to "<")
      { provider = '  ', hl = { fg = 'gray' } }, -- right trunctation, also optional (defaults to ...... yep, ">")
      function()
        return vim.api.nvim_tabpage_get_var(0, 'bufs')
      end,
      false
    )

    local Tabpage = {
      provider = function(self)
        return '%' .. self.tabnr .. 'T ' .. self.tabpage .. ' %T'
      end,
      hl = function(self)
        if not self.is_active then
          return 'TabLine'
        else
          return 'TabLineSel'
        end
      end,
    }

    local TabpageClose = {
      provider = '%999X  %X',
      hl = 'TabLine',
    }

    local TabPages = {
      -- only show this component if there's 2 or more tabpages
      condition = function()
        return #vim.api.nvim_list_tabpages() >= 2
      end,
      { provider = '%=' },
      heirline_utils.make_tablist(Tabpage),
      TabpageClose,
    }

    local TabLineOffset = {
      condition = function(self)
        local win = vim.api.nvim_tabpage_list_wins(0)[1]
        local bufnr = vim.api.nvim_win_get_buf(win)
        self.winid = win

        local found_buffer_for_offset = heirline_conditions.buffer_matches({ filetype = { 'NvimTree' } }, bufnr)
        return found_buffer_for_offset
      end,

      provider = function(self)
        return string.rep(' ', vim.api.nvim_win_get_width(self.winid))
      end,
      -- provider = function(self)
      --   local title = self.title
      --   local width = vim.api.nvim_win_get_width(self.winid)
      --   local pad = math.ceil((width - #title) / 2)
      --   return string.rep(" ", pad) .. title .. string.rep(" ", pad)
      -- end,

      hl = function(self)
        if vim.api.nvim_get_current_win() == self.winid then
          return 'TablineSel'
        else
          return 'Tabline'
        end
      end,
    }

    local TabLine = { TabLineOffset, BufferLine, TabPages }

    require('heirline').setup({
      tabline = TabLine,
    })
  end,
}
