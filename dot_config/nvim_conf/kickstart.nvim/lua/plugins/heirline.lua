-- Always show tabline
vim.o.showtabline = 2
-- TODO: wtf is this?
vim.cmd([[au FileType * if index(['wipe', 'delete'], &bufhidden) >= 0 | set nobuflisted | endif]])

-- Autocmds to make the internal buffer list state in sync with the actual buffers.
local function is_valid_buffer(bufnr)
  if not bufnr or bufnr < 1 then return false end
  return vim.bo[bufnr].buflisted and vim.api.nvim_buf_is_valid(bufnr)
end
local bufferline_group = vim.api.nvim_create_augroup("bufferline", { clear = true })
vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter" }, {
  desc = "Update buffers when adding new buffers",
  group = bufferline_group,
  callback = function(args)
    local success, bufs = pcall(function() return vim.api.nvim_tabpage_get_var(0, 'bufs') end)
    if not success then
      bufs = {}
    end
    if not vim.tbl_contains(bufs, args.buf) then
      table.insert(bufs, args.buf)
    end
    bufs = vim.tbl_filter(is_valid_buffer, bufs)
    vim.api.nvim_tabpage_set_var(0, 'bufs', bufs)
  end,
})
vim.api.nvim_create_autocmd("BufDelete", {
  desc = "Update buffers when deleting buffers",
  group = bufferline_group,
  callback = function(args)
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local bufs = vim.api.nvim_tabpage_get_var(tab, "bufs")
      if bufs then
        for i, bufnr in ipairs(bufs) do
          if bufnr == args.buf then
            table.remove(bufs, i)
            break
          end
        end
      end
      bufs = vim.tbl_filter(is_valid_buffer, bufs)
      vim.api.nvim_tabpage_set_var(tab, "bufs", bufs)
    end
    vim.cmd.redrawtabline()
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Open Neo-Tree on startup with directory",
  group = vim.api.nvim_create_augroup("neotree_start", { clear = true }),
  callback = function()
    local stats = vim.loop.fs_stat(vim.api.nvim_buf_get_name(0))
    if stats and stats.type == "directory" then require("neo-tree.setup.netrw").hijack() end
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Quit AstroNvim if more than one window is open and only sidebar windows are list",
  group = vim.api.nvim_create_augroup("auto_quit", { clear = true }),
  callback = function()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    -- Both neo-tree and aerial will auto-quit if there is only a single window left
    if #wins <= 1 then return end
    local sidebar_fts = { ["neo-tree"] = true }
    for _, winid in ipairs(wins) do
      if vim.api.nvim_win_is_valid(winid) then
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
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

---@type LazyPluginSpec
return {
  -- Tabline (Also has a winbar and statusline that are not currently used)
  "rebelot/heirline.nvim",
  config = function()
    -- [[ Configure heirline ]]
    -- See `:help heirline`
    local heirline_utils = require("heirline.utils")
    local heirline_conditions = require("heirline.conditions")

    -- we redefine the filename component, as we probably only want the tail and not the relative path
    local TablineFileName = {
      provider = function(self)
        -- self.filename will be defined later, just keep looking at the example!
        local filename = self.filename
        filename = filename == "" and "[No Name]" or vim.fn.fnamemodify(filename, ":t")
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
          return vim.api.nvim_get_option_value("modified", { buf = self.bufnr })
        end,
        provider = "[+]",
        hl = { fg = "green" },
      },
      {
        condition = function(self)
          return not vim.api.nvim_get_option_value("modifiable", { buf = self.bufnr })
              or vim.api.nvim_get_option_value("readonly", { buf = self.bufnr })
        end,
        provider = function(self)
          if vim.api.nvim_get_option_value("buftype", { buf = self.bufnr }) == "terminal" then
            return "  "
          else
            return ""
          end
        end,
        hl = { fg = "orange" },
      },
    }

    local FileIcon = {
      init = function(self)
        local filename = self.filename
        local extension = vim.fn.fnamemodify(filename, ":e")
        self.icon, self.icon_color = require("nvim-web-devicons").get_icon_color(filename, extension, { default = true })
      end,
      provider = function(self)
        return self.icon and (self.icon .. " ")
      end,
      hl = function(self)
        return { fg = self.icon_color }
      end
    }

    -- Here the filename block finally comes together
    local TablineFileNameBlock = {
      init = function(self)
        self.filename = vim.api.nvim_buf_get_name(self.bufnr)
      end,
      hl = function(self)
        if self.is_active then
          return "TabLineSel"
          -- why not?
          -- elseif not vim.api.nvim_buf_is_loaded(self.bufnr) then
          --     return { fg = "gray" }
        else
          return "TabLine"
        end
      end,
      on_click = {
        callback = function(_, minwid, _, button)
          if (button == "m") then -- close on mouse middle click
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
        name = "heirline_tabline_buffer_callback",
      },
      FileIcon, -- turns out the version defined in #crash-course-part-ii-filename-and-friends can be reutilized as is here!
      TablineFileName,
      TablineFileFlags,
    }

    -- a nice "x" button to close the buffer
    local TablineCloseButton = {
      condition = function(self)
        return not vim.api.nvim_get_option_value("modified", { buf = self.bufnr })
      end,
      { provider = " " },
      {
        provider = "",
        hl = { fg = "gray" },
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
          name = "heirline_tabline_close_buffer_callback",
        },
      },
    }

    -- The final touch!
    -- TODO: Use when I fix the patched font for Dank Mono by making icons smaller.
    -- For now, just pad with spaces.
    -- local TablineBufferBlock = heirline_utils.surround({ "", "" }, function(self)
    local TablineBufferBlock = heirline_utils.surround({}, function(self)
      if self.is_active then
        return heirline_utils.get_highlight("TabLineSel").bg
      else
        return heirline_utils.get_highlight("TabLine").bg
      end
    end, { { provider = " " }, TablineFileNameBlock, TablineCloseButton, { provider = " " } })

    -- and here we go
    local BufferLine = heirline_utils.make_buflist(
      TablineBufferBlock,
      { provider = "  ", hl = { fg = "gray" } }, -- left truncation, optional (defaults to "<")
      { provider = "  ", hl = { fg = "gray" } }, -- right trunctation, also optional (defaults to ...... yep, ">")
      function() return vim.api.nvim_tabpage_get_var(0, "bufs") end,
      false
    -- by the way, open a lot of buffers and try clicking them ;)
    )

    local Tabpage = {
      provider = function(self)
        return "%" .. self.tabnr .. "T " .. self.tabpage .. " %T"
      end,
      hl = function(self)
        if not self.is_active then
          return "TabLine"
        else
          return "TabLineSel"
        end
      end,
    }

    local TabpageClose = {
      provider = "%999X  %X",
      hl = "TabLine",
    }

    local TabPages = {
      -- only show this component if there's 2 or more tabpages
      condition = function()
        return #vim.api.nvim_list_tabpages() >= 2
      end,
      { provider = "%=" },
      heirline_utils.make_tablist(Tabpage),
      TabpageClose,
    }

    local TabLineOffset = {
      condition = function(self)
        local win = vim.api.nvim_tabpage_list_wins(0)[1]
        local bufnr = vim.api.nvim_win_get_buf(win)
        self.winid = win

        local found_buffer_for_offset = heirline_conditions.buffer_matches({ filetype = { "neo%-tree" } }, bufnr)
        return found_buffer_for_offset
      end,

      provider = function(self) return string.rep(" ", vim.api.nvim_win_get_width(self.winid)) end,
      -- provider = function(self)
      --   local title = self.title
      --   local width = vim.api.nvim_win_get_width(self.winid)
      --   local pad = math.ceil((width - #title) / 2)
      --   return string.rep(" ", pad) .. title .. string.rep(" ", pad)
      -- end,

      hl = function(self)
        if vim.api.nvim_get_current_win() == self.winid then
          return "TablineSel"
        else
          return "Tabline"
        end
      end,
    }

    local TabLine = { TabLineOffset, BufferLine, TabPages }

    require("heirline").setup({
      tabline = TabLine,
    })
  end
}
