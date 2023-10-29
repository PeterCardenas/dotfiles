local DOOM_HEADER = {
  [[=================     ===============     ===============   ========  ========]],
  [[\\ . . . . . . .\\   //. . . . . . .\\   //. . . . . . .\\  \\. . .\\// . . //]],
  [[||. . ._____. . .|| ||. . ._____. . .|| ||. . ._____. . .|| || . . .\/ . . .||]],
  [[|| . .||   ||. . || || . .||   ||. . || || . .||   ||. . || ||. . . . . . . ||]],
  [[||. . ||   || . .|| ||. . ||   || . .|| ||. . ||   || . .|| || . | . . . . .||]],
  [[|| . .||   ||. _-|| ||-_ .||   ||. . || || . .||   ||. _-|| ||-_.|\ . . . . ||]],
  [[||. . ||   ||-'  || ||  `-||   || . .|| ||. . ||   ||-'  || ||  `|\_ . .|. .||]],
  [[|| . _||   ||    || ||    ||   ||_ . || || . _||   ||    || ||   |\ `-_/| . ||]],
  [[||_-' ||  .|/    || ||    \|.  || `-_|| ||_-' ||  .|/    || ||   | \  / |-_.||]],
  [[||    ||_-'      || ||      `-_||    || ||    ||_-'      || ||   | \  / |  `||]],
  [[||    `'         || ||         `'    || ||    `'         || ||   | \  / |   ||]],
  [[||            .===' `===.         .==='.`===.         .===' /==. |  \/  |   ||]],
  [[||         .=='   \_|-_ `===. .==='   _|_   `===. .===' _-|/   `==  \/  |   ||]],
  [[||      .=='    _-'    `-_  `='    _-'   `-_    `='  _-'   `-_  /|  \/  |   ||]],
  [[||   .=='    _-'          '-__\._-'         '-_./__-'         `' |. /|  |   ||]],
  [[||.=='    _-'                                                     `' |  /==.||]],
  [[=='    _-'                        N E O V I M                         \/   `==]],
  [[\   _-'                                                                `-_   /]],
  [[ `''                                                                      ``' ]],
}

---Create a button that accepts a function as a keymap.
---@param shortcut string
---@param text string
---@param action_function function
---@return table
local function create_button(shortcut, text, action_function)
  local button_options = {
    position = "center",
    shortcut = shortcut,
    cursor = 3,
    width = 50,
    align_shortcut = "right",
    hl_shortcut = "Keyword",
    keymap = { "n", shortcut, '', { noremap = true, silent = true, nowait = true, callback = action_function } }
  }
  return {
    type = "button",
    val = text,
    on_press = action_function,
    opts = button_options,
  }
end

---@type LazyPluginSpec
return {
  "goolord/alpha-nvim",
  lazy = false,
  priority = 1001,
  config = function()
    -- Setup dashboard layout
    local dashboard = require("alpha.themes.dashboard")
    local header = DOOM_HEADER

    dashboard.section.header.val = header
    dashboard.section.buttons.val = {
      create_button("f", "  Find file",
        function()
          require('telescope.builtin').find_files()
        end
      ),
      create_button("n", "  New file",
        function()
          vim.cmd('ene <BAR> startinsert')
        end
      ),
      create_button("r", "  Recent files",
        function()
          require('telescope.builtin').oldfiles()
        end
      ),
      create_button("w", "  Find text",
        function()
          require("telescope").extensions.live_grep_args.live_grep_args()
        end
      ),
      create_button("g", "  LazyGit",
        function()
          require("lazygit").lazygit()
        end
      ),
      create_button("s", "  Restore Session",
        function()
          require("session_manager").load_current_dir_session()
        end
      ),
      create_button("l", "⏾  Lazy",
        function()
          require('lazy').show()
        end
      ),
      create_button("q", "  Quit",
        function()
          vim.cmd("qa")
        end
      ),
    }
    for _, button in ipairs(dashboard.section.buttons.val) do
      button.opts.hl = "AlphaButtons"
      button.opts.hl_shortcut = "AlphaShortcut"
    end
    dashboard.section.header.opts.hl = "AlphaHeader"
    dashboard.section.buttons.opts.hl = "AlphaButtons"
    dashboard.section.footer.opts.hl = "AlphaFooter"
    dashboard.opts.layout[1].val = 8
    require('alpha').setup(require('alpha.themes.dashboard').config)

    -- Add autocmds.
    local laststatus = vim.o.laststatus
    vim.o.laststatus = 0
    -- close Lazy and re-open when the dashboard is ready
    if vim.o.filetype == "lazy" then
      vim.cmd.close()
      vim.api.nvim_create_autocmd("User", {
        once = true,
        pattern = "AlphaReady",
        callback = function()
          require("lazy").show()
        end,
      })
    end

    vim.api.nvim_create_autocmd("BufUnload", {
      once = true,
      buffer = vim.api.nvim_get_current_buf(),
      callback = function()
        vim.opt.laststatus = laststatus
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      once = true,
      pattern = "LazyVimStarted",
      callback = function()
        local stats = require("lazy").stats()
        local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
        dashboard.section.footer.val = "⚡ Neovim loaded " .. stats.count .. " plugins in " .. ms .. "ms"
        pcall(vim.cmd.AlphaRedraw)
      end,
    })
  end,
}
