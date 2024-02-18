vim.api.nvim_create_user_command('CodyChat',
  function(command)
    -- Wait for the user to be authenticated
    while not require('sg.auth').get() do
      vim.wait(50)
    end
    local name = nil
    if not vim.tbl_isempty(command.fargs) then
      name = table.concat(command.fargs, " ")
    end

    require('sg.cody.commands').chat(name, { reset = command.bang })
  end,
  { nargs = "*", bang = true }
)


---@type LazyPluginSpec
return {
  'sourcegraph/sg.nvim',
  lazy = true,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
  },
  config = function()
    require('sg').setup({})
  end,
}
