---@type LazyPluginSpec[]
return {
  {
    'sourcegraph/sg.nvim',
    cmd = { 'CodyDo', 'CodyChat' },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    config = function()
      require('sg').setup({})
    end,
  },
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    branch = 'canary',
    cmd = { 'CopilotChat' },
    dependencies = {
      { 'zbirenbaum/copilot.lua' },
      { 'nvim-lua/plenary.nvim' },
    },
    config = function()
      vim.api.nvim_create_autocmd('BufEnter', {
        once = true,
        pattern = 'copilot-chat',
        callback = function(args)
          vim.cmd('vert rightbelow wincmd L')
          -- Get the total width of the Neovim window
          -- Does not work rn
          -- local total_width = vim.api.nvim_get_option_value('columns', { buf = args.buf })

          -- Calculate 30% of the total width
          -- local split_width = math.floor(total_width * 0.3)
          -- vim.cmd('vertical resize ' .. split_width)
        end,
      })
      require('CopilotChat').setup({
        window = {
          layout = 'vertical',
        },
      })
    end,
  },
  {
    'yetone/avante.nvim',
    build = 'make',
    event = { 'BufReadPre', 'BufNewFile' },
    cmd = { 'AvanteAsk' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'echasnovski/mini.icons',
    },
    config = function()
      local filepath = vim.fn.expand('~/.local/share/anthropic/api_key')
      local lines = vim.fn.readfile(filepath)
      if #lines == 0 or lines[1] == '' then
        vim.notify('Unable to load avante.nvim, Anthropic API key not found at ' .. filepath, vim.log.levels.ERROR)
        return
      end
      vim.env.ANTHROPIC_API_KEY = lines[1]
      require('avante').setup({
        behaviour = {
          auto_suggestions = not require('utils.config').USE_SUPERMAVEN,
        },
      })
    end,
  },
}
