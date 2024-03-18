vim.api.nvim_create_user_command('CodyInit',
  function()
    require('sg')
  end,
  { nargs = 0, desc = "Load the Cody Module" }
)

vim.api.nvim_create_user_command('CopilotChatInit',
  function()
    require('CopilotChat')
  end,
  { nargs = 0, desc = "Load the Copilot Chat Module" }
)

---@type LazyPluginSpec[]
return {
  {
    'sourcegraph/sg.nvim',
    lazy = true,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
    },
    config = function()
      require('sg').setup({})
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    lazy = true,
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    config = function()
      require('CopilotChat').setup({
        window = {
          layout = "float"
        }
      })
    end,
  }
}
