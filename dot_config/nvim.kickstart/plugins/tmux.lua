-- [[ Neovim TMUX Integration ]]
local function set_is_vim()
  local tmux_socket = vim.fn.split(vim.env.TMUX, ',')[1]
  vim.fn.system("tmux -S " .. tmux_socket .. " set-option -p @is_vim yes")
end

local function unset_is_vim()
  local tmux_socket = vim.fn.split(vim.env.TMUX, ',')[1]
  vim.fn.system("tmux -S " .. tmux_socket .. " set-option -p -u @is_vim")
end
local tmux_navigator_group = vim.api.nvim_create_augroup("tmux_navigator_is_vim", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  desc = "Tell TMUX we entered neovim",
  group = tmux_navigator_group,
  callback = set_is_vim
})
vim.api.nvim_create_autocmd("VimLeave", {
  desc = "Tell TMUX we left neovim",
  group = tmux_navigator_group,
  callback = unset_is_vim
})
vim.api.nvim_create_autocmd("VimSuspend", {
  desc = "Tell TMUX we suspended neovim",
  group = tmux_navigator_group,
  callback = unset_is_vim
})
vim.api.nvim_create_autocmd("VimResume", {
  desc = "Tell TMUX we resumed neovim",
  group = tmux_navigator_group,
  callback = set_is_vim
})

---@type LazyPluginSpec
return {
  -- Easy navigation between splits.
  'alexghergh/nvim-tmux-navigation',
  config = function()
    require 'nvim-tmux-navigation'.setup {
      disable_when_zoomed = true,   -- defaults to false
      keybindings = {
        left = "<C-h>",
        down = "<C-j>",
        up = "<C-k>",
        right = "<C-l>",
        last_active = "<C-\\>",
        next = "<C-Space>",
      }
    }
  end
}
