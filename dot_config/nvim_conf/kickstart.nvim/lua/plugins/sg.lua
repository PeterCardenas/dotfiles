local Config = require('utils.config')
local Shell = require('utils.shell')

---@param filepath string
---@return boolean, string
local function read_api_key(filepath)
  local api_key_filepath = vim.fn.expand(filepath)
  ---@type boolean, string[]
  local api_key_ok, api_key_lines = pcall(vim.fn.readfile, api_key_filepath)
  if not api_key_ok or #api_key_lines == 0 or api_key_lines[1] == '' then
    local api_key = vim.fn.input({ prompt = 'Enter key at ' .. api_key_filepath .. ': ', cancelreturn = '' })
    if api_key ~= '' then
      local write_ok, error_msg = require('utils.file').write_to_file(api_key_filepath, api_key)
      if write_ok then
        return true, api_key
      else
        vim.notify('Failed to write key to ' .. api_key_filepath .. (error_msg ~= '' and ': ' .. error_msg or ''), vim.log.levels.ERROR)
        return false, ''
      end
    end
    return false, ''
  end
  return true, api_key_lines[1]
end

vim.api.nvim_create_user_command('AvanteToggleAgentMode', function(opts)
  local config = require('avante.config')
  require('avante.config').override({
    behaviour = {
      auto_approve_tool_permissions = not config.behaviour.auto_approve_tool_permissions,
    },
  })
  config = require('avante.config')
  if config.behaviour.auto_approve_tool_permissions then
    vim.notify('Agent mode enabled', vim.log.levels.INFO)
  else
    vim.notify('Agent mode disabled', vim.log.levels.INFO)
  end
end, { desc = 'avante: toggle agent mode' })

vim.api.nvim_create_user_command('AvanteChangeProvider', function(args)
  local provider = vim.trim(args.args or '')
  require('avante.api').switch_provider(provider)
end, {
  desc = 'avante: change provider',
  nargs = 1,
  complete = function(_, line, _)
    local prefix = line:match('AvanteChangeProvider%s*(.*)$') or ''
    local avante_config = require('avante.config')
    local providers = vim.tbl_filter(
      ---@param key string
      function(key)
        return key:find(prefix, 1, true) == 1
      end,
      vim.tbl_keys(avante_config.providers)
    )
    for acp_provider_name, _ in pairs(avante_config.acp_providers) do
      if acp_provider_name:find(prefix, 1, true) == 1 then
        providers[#providers + 1] = acp_provider_name
      end
    end
    local filtered_providers = {} ---@type string[]
    for _, provider in ipairs(providers) do
      if vim.startswith(provider, 'bedrock_') or vim.startswith(provider, 'azure_') or provider == 'claude-code' then
        filtered_providers[#filtered_providers + 1] = provider
      end
    end
    return filtered_providers
  end,
})

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
    branch = 'handle-utf8-errors',
    keys = {
      { '<leader>aa', '<Plug>(AvanteAsk)', mode = { 'n', 'v' }, desc = 'avante: ask' },
      { '<leader>an', '<Plug>(AvanteAskNew)', mode = { 'n', 'v' }, desc = 'avante: ask new' },
      { '<leader>ae', '<Plug>(AvanteEdit)', mode = { 'n', 'v' }, desc = 'avante: edit' },
    },
    cmd = { 'AvanteAsk', 'AvanteEdit' },
    build = 'make BUILD_FROM_SOURCE=true',
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
      -- local anthropic_key_ok, anthropic_key = read_api_key('~/.local/share/anthropic/api_key')
      -- if not anthropic_key_ok then
      --   vim.notify('Unable to load avante.nvim, Anthropic API key not found', vim.log.levels.ERROR)
      --   return
      -- end
      -- vim.env.ANTHROPIC_API_KEY = anthropic_key
      local brave_search_key_ok, brave_search_key = read_api_key('~/.local/share/brave_search/api_key')
      if not brave_search_key_ok then
        vim.notify('Brave Search API key not found', vim.log.levels.ERROR)
      else
        vim.env.BRAVE_API_KEY = brave_search_key
      end
      local azure_openai_key_ok, azure_openai_key = read_api_key('~/.local/share/azure/api_key')
      if not azure_openai_key_ok then
        vim.notify('Azure OpenAI API key not found', vim.log.levels.ERROR)
      end
      local azure_embedding_key_ok, azure_embedding_key = read_api_key('~/.local/share/azure/embedding_key')
      if not azure_embedding_key_ok then
        vim.notify('Azure Embedding API key not found', vim.log.levels.ERROR)
      else
        vim.env.OPENAI_API_KEY = azure_embedding_key
      end

      -- HACK: bedrock provider fails early if BEDROCK_KEYS is not set
      require('avante.providers.bedrock').is_env_set = function()
        return true
      end

      local function parse_bedrock_key()
        local base_args = 'aws configure get '
        local region = 'us-east-1'
        local specific_args = ' --profile default --region ' .. region

        local success, output = Shell.sync_cmd(base_args .. 'aws_access_key_id' .. specific_args)
        local api_key = ''
        if success then
          api_key = output[1]
        else
          vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
          return nil
        end

        success, output = Shell.sync_cmd(base_args .. 'aws_secret_access_key' .. specific_args)
        if success then
          api_key = api_key .. ',' .. output[1]
        else
          vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
          return nil
        end

        api_key = api_key .. ',' .. region

        success, output = Shell.sync_cmd(base_args .. 'aws_session_token' .. specific_args)
        if success then
          api_key = api_key .. ',' .. output[1]
        else
          vim.notify('Failed to run AWS command: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
          return nil
        end

        return api_key
      end

      local AvanteToolsHelpers = require('avante.llm_tools.helpers')
      -- TODO: Properly respect gitignore for repo map
      -- TODO: building repo map should be async
      -- TODO: diffs should join with relevant diffs next to them
      -- TODO: allow cancelling, but keep chat history
      -- TODO: becomes slower the longer the output is.
      -- TODO: sidepanel duplicates
      local provider = 'azure_gpt_4o'
      require('avante').setup({
        mode = 'agentic',
        selection = {
          hint_display = 'none',
        },
        windows = {
          edit = {
            -- TODO: Change background color of title to be Normal and border to be FloatBorder
            border = 'rounded',
          },
        },
        provider = provider,
        auto_suggestions_provider = provider,
        behaviour = {
          auto_suggestions = not Config.USE_SUPERMAVEN,
          -- TODO: Use this when it's fast and less buggy
          enable_cursor_planning_mode = false,
          -- TODO: auto apply/ask to apply when running tools, maybe add a continue keymap and pause when applying diffs
          auto_apply_diff_after_generation = false,
          auto_approve_tool_permissions = false,
          confirmation_ui_style = 'popup',
          enable_claude_text_editor_tool_mode = false,
          enable_token_counting = false,
        },
        rag_service = {
          enabled = false,
          provider = 'azure',
          embed_model = 'text-embedding-3-large',
          endpoint = 'https://eastus.api.cognitive.microsoft.com/',
        },
        system_prompt = 'instead of suggesting what the file would be, always make the edit yourself. DO NOT run tests, i will run tests myself',
        acp_providers = {
          ['claude-code'] = {
            CLAUDE_CODE_USE_BEDROCK = 1,
            AWS_REGION = 'us-east-1',
            CLAUDE_CODE_MAX_OUTPUT_TOKENS = 4096,
            MAX_THINKING_TOKENS = 1024,
            ANTHROPIC_MODEL = 'us.anthropic.claude-sonnet-4-5-20250929-v1:0',
            ANTHROPIC_SMALL_FAST_MODEL = 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
          },
        },
        providers = {
          bedrock_sonnet = {
            __inherited_from = 'bedrock',
            model = 'us.anthropic.claude-sonnet-4-5-20250929-v1:0',
            aws_region = 'us-east-1',
            parse_api_key = parse_bedrock_key,
          },
          bedrock_haiku = {
            __inherited_from = 'bedrock',
            -- model = 'us.anthropic.claude-haiku-4-5-20251001-v1:0',
            model = 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
            aws_region = 'us-east-1',
            parse_api_key = parse_bedrock_key,
          },
          bedrock_opus = {
            __inherited_from = 'bedrock',
            model = 'us.anthropic.claude-opus-4-1-20250805-v1:0',
            aws_region = 'us-east-1',
            parse_api_key = parse_bedrock_key,
          },
          azure_gpt_4o = {
            __inherited_from = 'azure',
            parse_api_key = function()
              return azure_openai_key
            end,
            endpoint = 'https://westus.api.cognitive.microsoft.com/',
            model = 'gpt-4o',
            deployment = 'gpt-4o-2024-08-06',
            -- Make smaller than max (128k) because token count calculation is undershooting
            context_window = 100000,
            extra_request_body = {
              max_completion_tokens = 16384,
            },
          },
          azure_gpt_4o_mini = {
            __inherited_from = 'azure',
            parse_api_key = function()
              return azure_openai_key
            end,
            endpoint = 'https://eastus.api.cognitive.microsoft.com/',
            model = 'gpt-4o-mini',
            deployment = 'gpt-4o-mini-2024-07-18',
            -- Make smaller than max (128k) because token count calculation is undershooting
            context_window = 110000,
            extra_request_body = {
              max_completion_tokens = 16384,
            },
          },
          azure_o3_mini = {
            __inherited_from = 'azure',
            parse_api_key = function()
              return azure_openai_key
            end,
            endpoint = 'https://eastus.api.cognitive.microsoft.com/',
            model = 'o3-mini',
            deployment = 'o3-mini-2025-01-31',
            -- Make smaller than max (128k) because token count calculation is undershooting
            context_window = 110000,
            extra_request_body = {
              max_completion_tokens = 16384,
            },
          },
          azure_gpt_5 = {
            __inherited_from = 'azure',
            parse_api_key = function()
              local azure_openai_gpt_5_key_ok, azure_openai_gpt_5_key = read_api_key('~/.local/share/azure/gpt_5_api_key')
              if not azure_openai_gpt_5_key_ok then
                vim.notify('Azure OpenAI GPT 5 API key not found', vim.log.levels.ERROR)
              end
              return azure_openai_gpt_5_key
            end,
            endpoint = 'https://eastus2.api.cognitive.microsoft.com/',
            model = 'gpt-5',
            deployment = 'gpt-5-2025-08-07',
            -- Make smaller than max (128k) because token count calculation is undershooting
            context_window = 110000,
            extra_request_body = {
              max_completion_tokens = 16384,
            },
          },
          azure_gpt_5_1 = {
            __inherited_from = 'azure',
            parse_api_key = function()
              local azure_openai_gpt_5_1_key_ok, azure_openai_gpt_5_1_key = read_api_key('~/.local/share/azure/gpt_5_1_api_key')
              if not azure_openai_gpt_5_1_key_ok then
                vim.notify('Azure OpenAI GPT 5.1 API key not found', vim.log.levels.ERROR)
              end
              return azure_openai_gpt_5_1_key
            end,
            endpoint = 'https://eastus2.api.cognitive.microsoft.com/',
            model = 'gpt-5.1',
            deployment = 'gpt-5.1-2025-11-13',
            -- Make smaller than max (128k) because token count calculation is undershooting
            context_window = 110000,
            extra_request_body = {
              max_completion_tokens = 16384,
            },
          },
        },
        web_search_engine = {
          provider = 'brave',
        },
        -- TODO: read_definitions is broken
        disabled_tools = { 'python', 'bash', 'dispatch_agent', 'git_commit', 'git_diff', 'view', 'read_definitions' },
        custom_tools = {
          {
            name = 'run_command',
            description = 'Run a command in the terminal in a given directory',
            ---@type AvanteLLMToolFunc<{rel_path: string, command: string}>
            func = function(opts, func_opts)
              local on_complete = func_opts.on_complete
              local on_log = func_opts.on_log
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
              end, nil, func_opts.session_ctx, 'run_command')
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
        selector = {
          provider = 'fzf_lua',
        },
        mappings = {
          suggestion = {
            accept = not Config.USE_SUPERMAVEN and '<C-y>' or '<M-l>',
          },
        },
      })
      vim.api.nvim_del_user_command('AvanteSwitchProvider')
    end,
  },
  {
    'olimorris/codecompanion.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    cmd = { 'CodeCompanion', 'CodeCompanionCmd', 'CodeCompanionChat', 'CodeCompanionActions' },
    config = function()
      local azure_openai_key_ok, azure_openai_key = read_api_key('~/.local/share/azure/api_key')
      if not azure_openai_key_ok then
        vim.notify('Azure OpenAI API key not found', vim.log.levels.ERROR)
      else
        vim.env.AZURE_OPENAI_API_KEY = azure_openai_key
      end
      require('codecompanion').setup({
        display = {
          chat = {
            window = {
              position = 'right',
            },
          },
        },
        adapters = {
          azure_openai = function()
            return require('codecompanion.adapters').extend('azure_openai', {
              env = {
                api_key = 'AZURE_OPENAI_API_KEY',
                endpoint = 'https://westus.api.cognitive.microsoft.com/',
              },
              schema = {
                model = {
                  default = 'gpt-4o-mini-2024-07-18',
                  api_version = '2024-02-01',
                },
              },
            })
          end,
        },
        strategies = {
          chat = {
            adapter = 'azure_openai',
          },
          inline = {
            adapter = 'azure_openai',
          },
        },
      })
    end,
  },
}
