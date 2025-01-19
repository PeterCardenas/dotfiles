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
    position = 'center',
    shortcut = shortcut,
    cursor = 3,
    width = 50,
    align_shortcut = 'right',
    hl_shortcut = 'Keyword',
    keymap = { 'n', shortcut, '', { noremap = true, silent = true, nowait = true, callback = action_function } },
  }
  return {
    type = 'button',
    val = text,
    on_press = action_function,
    opts = button_options,
  }
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'alpha',
  callback = function(opts)
    ---@type integer
    local bufnr = opts.buf
    vim.api.nvim_buf_set_option(bufnr, 'number', false)
    vim.api.nvim_buf_set_option(bufnr, 'foldcolumn', '0')
    vim.api.nvim_buf_set_option(bufnr, 'statuscolumn', '')
  end,
})

---@type LazyPluginSpec
return {
  'goolord/alpha-nvim',
  lazy = false,
  priority = 1001,
  config = function()
    -- Setup dashboard layout
    local dashboard = require('alpha.themes.dashboard')
    local header = DOOM_HEADER

    dashboard.section.header.val = header
    -- TODO: Create shared functions to combat desync
    dashboard.section.buttons.val = {
      create_button('f', '  Find file', function()
        require('plugins.telescope.setup').find_files(false)
      end),
      create_button('n', '  New file', function()
        vim.cmd('ene <BAR> startinsert')
      end),
      create_button('r', '  Recent files', function()
        require('plugins.telescope.setup').find_recent_files()
      end),
      create_button('w', '  Find text', function()
        require('plugins.telescope.setup').find_words(false)
      end),
      create_button('g', '  LazyGit', function()
        require('local.lazygit').open_lazygit()
      end),
      create_button('s', '  Restore Session', function()
        require('session_manager').load_current_dir_session()
        local lazygit_bufnr = vim.iter(vim.api.nvim_list_bufs()):find(function(bufnr) ---@param bufnr integer
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          return bufname:match('term://.*lazygit')
        end)
        if lazygit_bufnr ~= nil then
          require('bufdelete').bufdelete(lazygit_bufnr)
        end
      end),
      create_button('l', '⏾  Lazy', function()
        require('lazy').show()
      end),
      create_button('q', '  Quit', function()
        vim.cmd('qa')
      end),
    }
    for _, button in ipairs(dashboard.section.buttons.val) do
      button.opts.hl = 'AlphaButtons'
      button.opts.hl_shortcut = 'AlphaShortcut'
    end
    dashboard.section.header.opts.hl = 'AlphaHeader'
    dashboard.section.buttons.opts.hl = 'AlphaButtons'
    dashboard.section.footer.opts.hl = 'AlphaFooter'
    dashboard.section.footer.opts.spacing = 1
    dashboard.section.footer.type = 'group'
    local version_string = 'v' .. vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch
    if vim.version().prerelease then
      version_string = version_string .. '-' .. vim.version().prerelease .. '+' .. vim.version().build
    end
    dashboard.section.footer.val = {
      {
        type = 'text',
        val = version_string,
        opts = { hl = 'AlphaFooter', position = 'center' },
      },
    }
    dashboard.opts.layout[1].val = 2
    dashboard.opts.margin = nil
    require('alpha').setup(require('alpha.themes.dashboard').config)

    -- Add autocmds.
    local laststatus = vim.o.laststatus
    vim.o.laststatus = 0
    -- close Lazy and re-open when the dashboard is ready
    if vim.o.filetype == 'lazy' then
      vim.cmd.close()
      vim.api.nvim_create_autocmd('User', {
        once = true,
        pattern = 'AlphaReady',
        callback = function()
          require('lazy').show()
        end,
      })
    end

    vim.api.nvim_create_autocmd('BufUnload', {
      once = true,
      buffer = vim.api.nvim_get_current_buf(),
      callback = function()
        vim.opt.laststatus = laststatus
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      once = true,
      pattern = 'LazyVimStarted',
      callback = function()
        local stats = require('lazy').stats()
        local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
        local current_footer = dashboard.section.footer.val
        ---@type table
        local footer
        if type(current_footer) ~= 'table' then
          vim.notify('dashboard.section.footer.val is not a table: ' .. dashboard.section.footer.val, vim.log.levels.ERROR)
          footer = {}
        else
          -- Clone the table
          footer = vim.tbl_deep_extend('force', {}, current_footer)
        end
        table.insert(footer, {
          type = 'text',
          opts = { position = 'center', hl = 'AlphaFooter' },
          val = '⚡ Neovim loaded ' .. stats.count .. ' plugins in ' .. ms .. 'ms',
        })
        dashboard.section.footer.val = footer
        pcall(vim.cmd.AlphaRedraw)
      end,
    })
  end,
}
