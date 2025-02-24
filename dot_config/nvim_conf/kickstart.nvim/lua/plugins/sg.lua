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
        callback = function(_args)
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
    'PeterCardenas/avante.nvim',
    branch = 'allow-async-tools',
    build = 'make',
    event = { 'VeryLazy' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'echasnovski/mini.icons',
    },
    config = function()
      local api_key_filepath = vim.fn.expand('~/.local/share/anthropic/api_key')
      local lines = vim.fn.readfile(api_key_filepath)
      if #lines == 0 or lines[1] == '' then
        vim.notify('Unable to load avante.nvim, Anthropic API key not found at ' .. api_key_filepath, vim.log.levels.ERROR)
        return
      end
      vim.env.ANTHROPIC_API_KEY = lines[1]
      -- TODO: Properly respect gitignore for repo map
      -- TODO: building repo map should be async
      require('avante').setup({
        hints = {
          enabled = false,
        },
        behaviour = {
          auto_suggestions = not require('utils.config').USE_SUPERMAVEN,
          -- TODO: Use this when it's fast and less buggy
          enable_cursor_planning_mode = false,
          -- TODO: auto apply/ask to apply when running tools
          auto_apply_diff_after_generation = false,
        },
        run_command = {
          shell_cmd = 'fish -c',
        },
        file_selector = {
          provider = 'fzf',
          provider_opts = {
            get_filepaths = function(params) ---@param params avante.file_selector.opts.IGetFilepathsParams
              local cwd = params.cwd
              -- TODO: Use params.selected_filepaths to filter out files that are already selected

              local cmd = require('plugins.telescope.setup').rg_files_cmd(false) .. ' ' .. vim.fn.fnameescape(cwd)

              local output = vim.fn.system(cmd)

              -- Add directories to the list of filepaths
              -- TODO: Add this upstream to avante.nvim
              local filepaths = vim.split(output, '\n', { trimempty = true })
              local directory_map = {} ---@type table<string, boolean>
              for _, filepath in ipairs(filepaths) do
                local dir = vim.fn.fnamemodify(filepath, ':h')
                local home_dir = vim.fn.expand('~')
                while dir ~= '' and dir ~= '/' and dir ~= home_dir and dir ~= cwd do
                  local dir_with_slash = dir .. '/'
                  if not directory_map[dir_with_slash] then
                    directory_map[dir_with_slash] = true
                  end
                  dir = vim.fn.fnamemodify(dir, ':h')
                end
              end
              local directories = vim.tbl_keys(directory_map)
              vim.list_extend(filepaths, directories)

              return vim
                .iter(filepaths)
                :map(function(filepath)
                  return vim.fn.fnamemodify(filepath, ':~:.')
                end)
                :totable()
            end,
          },
        },
      })
    end,
  },
}
