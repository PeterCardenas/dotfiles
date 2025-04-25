local Config = require('utils.config')

local profile_env = os.getenv('NVIM_PROFILE')
if profile_env ~= nil then
  local profile_startup = profile_env:lower():match('^start$') ~= nil
  if Config.USE_SNACKS_PROFILER then
    local snacks = vim.fn.stdpath('data') .. '/lazy/snacks.nvim'
    vim.opt.rtp:append(snacks)
    if profile_startup then
      ---@diagnostic disable-next-line: missing-fields
      require('snacks.profiler').startup({
        startup = {
          event = 'VeryLazy',
        },
      })
    end
  else
    local profiler = vim.fn.stdpath('data') .. '/lazy/profile.nvim'
    if vim.fn.isdirectory(profiler) == 1 then
      vim.opt.rtp:append(profiler)
      require('profile').instrument_autocmds()
      if profile_startup then
        require('profile').start('*')
        vim.api.nvim_create_autocmd('User', {
          once = true,
          pattern = 'VeryLazy',
          callback = function()
            vim.cmd('ToggleProfile')
          end,
        })
      else
        require('profile').instrument('*')
      end
    end
  end
end

require('mappings')
require('options')
require('local')
require('lazy_setup')
