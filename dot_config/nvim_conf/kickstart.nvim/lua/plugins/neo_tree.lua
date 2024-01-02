vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Open Neo-Tree on startup with directory",
  group = vim.api.nvim_create_augroup("neotree_start", { clear = true }),
  callback = function()
    local stats = vim.loop.fs_stat(vim.api.nvim_buf_get_name(0))
    if stats and stats.type == "directory" then require("neo-tree.setup.netrw").hijack() end
  end,
})

---@type LazyPluginSpec
return {
  -- File Explorer
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
    "MunifTanjim/nui.nvim",
  },
  config = function()
    local function system_open(path)
      path = path or vim.fn.expand "<cfile>"
      require('utils').system_open(path)
    end

    require("neo-tree").setup({
      close_if_last_window = true,
      enable_normal_mode_for_inputs = true,
      window = {
        mappings = {
          -- Prefer existing keymaps using leader.
          ["<space>"] = false,
          -- Prefer neovim search of neo-tree search.
          ['/'] = false,
          ['?'] = false,
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        async_directory_scan = "always",
        hijack_netrw_behavior = "open_default",
        window = {
          mappings = {
            O = "system_open",
            h = "toggle_hidden",
          },
        },
        commands = {
          system_open = function(state) system_open(state.tree:get_node():get_id()) end,
        },
      }
    })
  end
}
