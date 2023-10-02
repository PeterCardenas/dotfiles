---@type LazyPluginSpec
return {
  -- File Explorer
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  lazy = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",   -- not strictly required, but recommended
    "MunifTanjim/nui.nvim",
  },
  config = function()
    local function system_open(path)
      path = path or vim.fn.expand "<cfile>"
      if vim.fn.has "mac" == 1 then
        -- if mac use the open command
        vim.fn.jobstart({ "open", path }, { detach = true })
      elseif vim.fn.has "unix" == 1 then
        -- if unix then use xdg-open
        vim.fn.jobstart({ "xdg-open", path }, { detach = true })
      else
        -- if any other operating system notify the user that there is currently no support
        vim.schedule(function()
          vim.notify("System open is not supported on this OS!", vim.log.levels.ERROR,
            { title = "System Open" })
        end)
      end
    end

    require("neo-tree").setup {
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
    }
  end
}
