vim.api.nvim_create_user_command('DapToggleUI', function()
  require('dapui').toggle()
end, {
  nargs = 0,
})

local function debug_nvim_lua()
  require('osv').launch({ port = 8086 })
end

vim.api.nvim_create_user_command('DapDebugNvimLua', function()
  debug_nvim_lua()
end, {
  nargs = 0,
})

-- Primarily focused on configuring the debugger for Go, but can
-- be extended to other languages as well. That's why it's called
---@type LazyPluginSpec
return {
  'mfussenegger/nvim-dap',
  dependencies = {
    -- Creates a beautiful debugger UI
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    {
      'theHamsta/nvim-dap-virtual-text',
      dependencies = {
        'nvim-treesitter/nvim-treesitter',
      },
      config = function()
        require('nvim-dap-virtual-text').setup({})
      end,
    },

    -- Installs the debug adapters for you
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',
    'jbyuki/one-small-step-for-vimkind',
  },
  lazy = true,
  cmd = { 'DapContinue' },
  keys = {
    {
      '<leader>dc',
      function()
        require('dap').continue()
      end,
      desc = 'Debug: Start/Continue',
    },
    {
      '<leader>dt',
      function()
        require('dap').terminate()
      end,
      desc = 'Debug: Terminate',
    },
    {
      '<leader>di',
      function()
        require('dap').step_into()
      end,
      desc = 'Debug: Step Into',
    },
    {
      '<leader>ds',
      function()
        require('dap').step_over()
      end,
      desc = 'Debug: Step Over',
    },
    {
      '<leader>do',
      function()
        require('dap').step_out()
      end,
      desc = 'Debug: Step Out',
    },
    {
      '<leader>dbb',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = 'Debug: Toggle Breakpoint',
    },
    {
      '<leader>dbc',
      function()
        local condition = vim.trim(vim.fn.input('Breakpoint condition: '))
        if condition:len() == 0 then
          vim.notify('No breakpoint condition', vim.log.levels.ERROR)
          return
        end
        require('dap').set_breakpoint(condition)
      end,
      desc = 'Debug: Add conditional breakpoint',
    },
    {
      '<leader>dbl',
      function()
        local log_message = vim.trim(vim.fn.input('Log message: '))
        if log_message:len() == 0 then
          vim.notify('No log message', vim.log.levels.ERROR)
          return
        end
        require('dap').set_breakpoint(nil, nil, log_message)
      end,
      desc = 'Debug: Add logpoint',
    },
  },
  config = function()
    local dap = require('dap')
    local dapui = require('dapui')

    require('mason-nvim-dap').setup({
      -- Makes a best effort to setup the various debuggers with
      -- reasonable debug configurations
      automatic_setup = true,

      automatic_installation = false,

      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},

      -- You'll need to check that you have the required things installed
      -- online, please don't ask me how to install them :)
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        'delve',
      },
    })

    -- Basic debugging keymaps, feel free to change to your liking!

    -- Dap UI setup
    -- For more information, see |:help nvim-dap-ui|
    ---@diagnostic disable-next-line: missing-fields
    dapui.setup({
      -- Set icons to characters that are more likely to work in every terminal.
      --    Feel free to remove or use ones that you like more! :)
      --    Don't feel like these are good choices.
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      ---@diagnostic disable-next-line: missing-fields
      controls = {
        icons = {
          pause = '⏸',
          play = '▶',
          step_into = '⏎',
          step_over = '⏭',
          step_out = '⏮',
          step_back = 'b',
          run_last = '▶▶',
          terminate = '⏹',
          disconnect = '⏏',
        },
      },
    })

    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'dap-repl',
      callback = function(args)
        vim.bo[args.buf].buflisted = false
      end,
    })

    -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
    vim.keymap.set('n', '<F7>', dapui.toggle, { desc = 'Debug: See last session result.' })

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close

    -- Install golang specific config
    require('dap-go').setup()

    -- Setup neovim lua debugging
    dap.configurations.lua = {
      {
        type = 'nlua',
        request = 'attach',
        name = 'Attach to running Neovim instance',
      },
    }
    dap.adapters.nlua = function(callback, config)
      ---@diagnostic disable-next-line: undefined-field
      callback({ type = 'server', host = config.host or '127.0.0.1', port = config.port or 8086 })
    end
  end,
}
