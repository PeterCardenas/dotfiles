local Config = require('utils.config')
local Finder = require('plugins.telescope.setup')

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
    'yetone/avante.nvim',
    build = 'make',
    event = { 'VeryLazy' },
    cond = function()
      local api_key_filepath = vim.fn.expand('~/.local/share/anthropic/api_key')
      return vim.fn.filereadable(api_key_filepath) == 1
    end,
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

      ---@type string
      vim.env.ANTHROPIC_API_KEY = lines[1]
      local AvanteToolsHelpers = require('avante.llm_tools.helpers')
      -- TODO: Properly respect gitignore for repo map
      -- TODO: building repo map should be async
      -- TODO: diffs should join with relevant diffs next to them
      -- TODO: allow cancelling, but keep chat history
      -- TODO: becomes slower the longer the output is.
      -- TODO: sidepanel duplicates
      require('avante').setup({
        hints = {
          enabled = false,
        },
        behaviour = {
          auto_suggestions = not Config.USE_SUPERMAVEN,
          -- TODO: Use this when it's fast and less buggy
          enable_cursor_planning_mode = false,
          -- TODO: auto apply/ask to apply when running tools, maybe add a continue keymap and pause when applying diffs
          auto_apply_diff_after_generation = false,
        },
        disabled_tools = { 'python', 'bash' },
        custom_tools = {
          {
            name = 'run_command',
            description = 'Run a command in the terminal in a given directory',
            ---@type AvanteLLMToolFunc<{rel_path: string, command: string}>
            func = function(opts, on_log, on_complete)
              if not on_complete then
                return false, 'Cannot use run_command tool'
              end
              local abs_path = AvanteToolsHelpers.get_abs_path(opts.rel_path)
              if not AvanteToolsHelpers.has_permission_to_access(abs_path) then
                return false, 'No permission to access path: ' .. abs_path
              end
              if not require('plenary.path'):new(abs_path):exists() then
                return false, 'Path not found: ' .. abs_path
              end
              if on_log then
                on_log('command: ' .. opts.command)
              end
              local message = 'Are you sure you want to run the command: `' .. opts.command .. '` in the directory: ' .. abs_path
              AvanteToolsHelpers.confirm(message, function(ok)
                if not ok then
                  on_complete(false, 'User canceled')
                end
                ---change cwd to abs_path
                ---@param output string
                ---@param exit_code integer
                ---@return string | boolean | nil result
                ---@return string | nil error
                local function handle_result(output, exit_code)
                  if exit_code ~= 0 then
                    if output then
                      return false, 'Error: ' .. output .. '; Error code: ' .. tostring(exit_code)
                    end
                    return false, 'Error code: ' .. tostring(exit_code)
                  end
                  return output, nil
                end
                require('avante.utils').shell_run_async(opts.command, 'fish -c', function(output, exit_code)
                  local result, err = handle_result(output, exit_code)
                  on_complete(result, err)
                end, abs_path)
              end)
            end,
            param = {
              type = 'table',
              fields = {
                {
                  name = 'rel_path',
                  description = 'Relative path to the directory',
                  type = 'string',
                },
                {
                  name = 'command',
                  description = 'Command to run',
                  type = 'string',
                },
              },
            },
            returns = {
              {
                name = 'stdout',
                description = 'Output of the command',
                type = 'string',
              },
              {
                name = 'error',
                description = 'Error message if the command was not run successfully',
                type = 'string',
                optional = true,
              },
            },
          },
        },
        file_selector = {
          provider = 'fzf',
          provider_opts = {
            get_filepaths = function(params) ---@param params avante.file_selector.opts.IGetFilepathsParams
              local cwd = params.cwd
              -- TODO: Use params.selected_filepaths to filter out files that are already selected

              local cmd = Finder.rg_files_cmd(false) .. ' ' .. vim.fn.fnameescape(cwd)

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
