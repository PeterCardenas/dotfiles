local Config = require('utils.config')
local Log = require('utils.log')
local Spinner = require('utils.spinner')

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
    'PeterCardenas/agentic.nvim',
    branch = 'vibin',
    upstream = 'carlos-algms/agentic.nvim',
    upstream_branch = 'main',
    cond = function()
      return Config.USE_AGENTIC
    end,
    keys = {
      -- Keep AI actions under the same leader prefix.
      {
        '<leader>at',
        function()
          require('agentic').toggle()
        end,
        mode = { 'n', 'v' },
        desc = 'agentic: toggle',
      },
      {
        '<leader>ac',
        function()
          require('agentic').add_selection_or_file_to_context()
        end,
        mode = { 'n', 'v' },
        desc = 'agentic: add context',
      },
      {
        '<leader>an',
        function()
          require('agentic').new_session()
        end,
        mode = { 'n', 'v' },
        desc = 'agentic: new session',
      },
      {
        '<leader>ah',
        function()
          require('agentic').restore_session()
        end,
        mode = { 'n' },
        desc = 'agentic: restore session (history)',
      },
      {
        '<leader>ax',
        function()
          require('agentic').switch_provider()
        end,
        mode = { 'n' },
        desc = 'agentic: switch provider',
      },
      {
        '<leader>al',
        function()
          require('agentic').rotate_layout()
        end,
        mode = { 'n' },
        desc = 'agentic: rotate layout',
      },
      {
        '<leader>as',
        function()
          require('agentic').stop_generation()
        end,
        mode = { 'n' },
        desc = 'agentic: stop generation',
      },
      {
        '<leader>ad',
        function()
          require('agentic').add_buffer_diagnostics()
        end,
        mode = { 'n' },
        desc = 'agentic: add file diagnostics',
      },
    },
    cmd = { 'AgenticFullscreen' },
    dependencies = {
      {
        'PeterCardenas/img-clip.nvim',
        branch = 'dev',
        upstream = 'hakonharnes/img-clip.nvim',
        upstream_branch = 'main',
      },
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      -- Track cost per session for tmux status bar aggregation.
      -- Each nvim writes its own PID file keyed by UTC date so sessions
      -- spanning midnight split correctly. Format: "YYYY-MM-DD <cost>\n" per line.
      ---@type table<string, table<string, number>>
      local _spend_by_session = {} -- session_id -> { date -> cost }
      local _spend_dir = (os.getenv('XDG_DATA_HOME') or (os.getenv('HOME') .. '/.local/share')) .. '/claude-spend'
      local _spend_file = _spend_dir .. '/' .. vim.fn.getpid()
      vim.fn.mkdir(_spend_dir, 'p')

      local function _utc_date()
        return os.date('!%Y-%m-%d')
      end

      local function _flush_spend()
        -- Aggregate by date across all sessions
        ---@type table<string, number>
        local by_date = {} -- date -> cost
        for _, dates in pairs(_spend_by_session) do
          for date, cost in pairs(dates) do
            if date ~= '_prev' then
              by_date[date] = (by_date[date] or 0) + cost
            end
          end
        end
        ---@type string[]
        local lines = {}
        for date, cost in pairs(by_date) do
          lines[#lines + 1] = string.format('%s %.4f', date, cost)
        end
        local content = table.concat(lines, '\n')
        vim.uv.fs_open(_spend_file, 'w', tonumber('644', 8), function(err, fd)
          if err or not fd then
            return
          end
          vim.uv.fs_write(fd, content, -1, function()
            vim.uv.fs_close(fd)
          end)
        end)
      end

      vim.api.nvim_create_user_command('AgenticFullscreen', function()
        require('agentic').toggle()
        vim.defer_fn(function()
          require('agentic.session_registry').get_session_for_tab_page(nil, function(s)
            s.widget:_toggle_full_width()
          end)
        end, 200)
      end, {})

      require('agentic').setup({
        provider = 'cursor-acp',

        -- Right-side chat layout.
        windows = {
          position = 'right',
          width = '40%',
          chat = { win_opts = {} },
          input = { height = 10, win_opts = {} },
          code = { max_height = 15, win_opts = {} },
          files = { max_height = 10, win_opts = {} },
          todos = { display = true, max_height = 10, win_opts = {} },
        },

        -- Enable session restoration
        session_restore = {
          storage_path = nil, -- Uses default ~/.cache/nvim/agentic/sessions/
        },

        -- Enable diff preview with split layout
        diff_preview = {
          enabled = true,
          layout = 'split',
          center_on_navigate_hunks = true,
        },

        folding = {
          tool_calls = {
            enabled = true,
            closed_by_default = false,
            preview = true,
            min_lines = 5,
            kinds = {
              edit = {
                preview = false,
              },
              execute = {
                min_lines = 5,
              },
            },
          },
          ---@param info agentic.UserConfig.FoldtextInfo
          ---@return [string, string][]
          foldtext = function(info)
            local suffix = (' 󰁂 %d '):format(info.line_count)
            local suffix_width = vim.fn.strdisplaywidth(suffix)
            local target_width = info.width - suffix_width

            local cur_width = 0
            local new_virt_text = {}
            for _, chunk in ipairs(info.virt_text) do
              local chunk_width = vim.fn.strdisplaywidth(chunk[1])
              if cur_width + chunk_width > target_width then
                table.insert(new_virt_text, { info.truncate(chunk[1], target_width - cur_width), chunk[2] })
                break
              end
              table.insert(new_virt_text, chunk)
              cur_width = cur_width + chunk_width
            end

            table.insert(new_virt_text, { suffix, 'MoreMsg' })
            return new_virt_text
          end,
        },

        -- Debug mode off by default
        debug = false,

        -- ACP provider configurations
        acp_providers = {
          -- Claude ACP with Opus model via Bedrock
          ['claude-agent-acp'] = {
            command = 'claude-agent-acp',
            args = {},
            -- env = { ENABLE_LSP_TOOL = '1' },
            default_config_options = {
              model = 'opus[1m]',
              mode = 'bypassPermissions',
            },
            mcp_servers = {
              {
                type = 'http',
                name = 'figma',
                url = 'https://figma.com/mcp',
                headers = {},
              },
              -- {
              --   type = 'stdio',
              --   name = 'fff',
              --   command = 'fff-mcp',
              --   args = {},
              --   env = {},
              -- },
            },
          },
          ['cursor-acp'] = {
            default_config_options = {
              model = 'gpt-5.4',
              reasoning = 'high',
              fast = 'false',
            },
            auto_approve = true,
          },
          -- OpenCode with Bedrock config
          ['opencode'] = {
            command = 'opencode',
            args = { 'acp' },
            env = {
              OPENCODE_CONFIG = vim.fn.expand('~/.config/opencode/opencode-bedrock.jsonc'),
            },
          },
          -- Gemini ACP
          ['gemini'] = {
            command = 'gemini',
            args = { '--experimental-acp' },
            env = {},
          },
          -- Codex ACP
          ['codex-acp'] = {
            command = 'codex-acp',
            args = {},
            env = {},
          },
        },

        -- Keybindings configuration
        keymaps = {
          widget = {
            close = 'q',
            switch_provider = '<localleader>s',
          },
          prompt = {
            submit = { '<CR>', { '<C-s>', mode = { 'i', 'n', 'v' } } },
            paste_image = { { '<localleader>p', mode = { 'n' } } },
            accept_completion = { { '<Tab>', mode = { 'i' } } },
          },
          diff_preview = {
            next_hunk = ']c',
            prev_hunk = '[c',
          },
        },

        -- Custom headers: show provider | model | mode
        headers = {
          chat = function(parts)
            ---@param value string?
            ---@return boolean
            local function is_enabled(value)
              if not value then
                return false
              end
              local normalized = value:lower()
              return normalized == '1' or normalized == 'true' or normalized == 'on' or normalized == 'yes' or normalized == 'enabled'
            end
            ---@param value string?
            local function has_meaningful_value(value)
              if not value then
                return false
              end
              local normalized = value:lower()
              return normalized ~= ''
                and normalized ~= '0'
                and normalized ~= 'false'
                and normalized ~= 'off'
                and normalized ~= 'no'
                and normalized ~= 'disabled'
                and normalized ~= 'none'
            end
            local ok, SessionRegistry = pcall(require, 'agentic.session_registry')
            if not ok then
              return parts.title
            end
            local session = SessionRegistry.sessions and SessionRegistry.sessions[vim.api.nvim_get_current_tabpage()]
            if not session then
              return parts.title
            end
            local provider = session.agent and session.agent.provider_config and session.agent.provider_config.name or '?'
            local config_opts = session.config_options
            local model_id = config_opts and config_opts.model and config_opts.model.currentValue or '?'
            local model_suffix = ''
            local all_options = config_opts and config_opts.all_options or nil
            local reasoning_value = all_options and all_options.reasoning and all_options.reasoning.currentValue or nil
            if has_meaningful_value(reasoning_value) then
              if reasoning_value == 'extra-high' then
                reasoning_value = 'xhigh'
              end
              model_suffix = model_suffix .. '-' .. reasoning_value
            end
            local fast_value = all_options and all_options.fast and all_options.fast.currentValue or nil
            if is_enabled(fast_value) then
              model_suffix = model_suffix .. '-fast'
            end
            local mode_id = config_opts and config_opts.mode and config_opts.mode.currentValue or '?'
            local mode_name = config_opts and config_opts.get_mode_name and config_opts:get_mode_name(mode_id) or mode_id
            local usage = vim.t[vim.api.nvim_get_current_tabpage()].agentic_usage
            local usage_str = ''
            if usage and usage.used then
              local used_k = math.floor(usage.used / 1000)
              local size_k = usage.size and math.floor(usage.size / 1000) or 0
              local cost_str = usage.cost and string.format(' $%.2f', usage.cost) or ''
              usage_str = size_k > 0 and string.format(' | %dk/%dk%s', used_k, size_k, cost_str) or string.format(' | %dk%s', used_k, cost_str)
            end
            return string.format('%s | %s%s | %s%s', provider, model_id, model_suffix, mode_name, usage_str)
          end,
        },

        -- Hooks for custom behavior
        hooks = {
          ---@param _data agentic.UserConfig.PromptSubmitData
          on_prompt_submit = function(_data)
            vim.api.nvim_ui_send(string.format('\027]9;4;3\027\\'))
          end,
          ---@param data agentic.UserConfig.ResponseCompleteData
          on_response_complete = function(data)
            if not data.success then
              vim.api.nvim_ui_send(string.format('\027]9;4;2;100\027\\'))
              return
            end
            vim.api.nvim_ui_send(string.format('\027]9;4;1;100\027\\'))
            local SessionRegistry = require('agentic.session_registry')
            local session = SessionRegistry.sessions and SessionRegistry.sessions[data.tab_page_id]
            if not session or not session.chat_history then
              return
            end
            -- Snapshot the history object before any later /new destroys and replaces the session.
            local chat_history = session.chat_history
            local messages = chat_history.messages
            if not messages or #messages == 0 then
              return
            end

            -- Build a condensed chat transcript for summarization (prefer recent messages)
            local parts = {}
            for _, msg in ipairs(messages) do
              if msg.type == 'user' then
                table.insert(parts, '<user>' .. (msg.text or '') .. '</user>')
              elseif msg.type == 'agent' then
                table.insert(parts, '<assistant>' .. (msg.text or '') .. '</assistant>')
              elseif msg.type == 'tool_call' and msg.argument then
                local arg = msg.argument
                -- Skip generic tool names that don't add context (e.g., "Edit", "Write", "Terminal")
                local is_generic = arg and arg:match('^%a+$') and #arg < 20
                if not is_generic then
                  local kind_labels = { edit = 'edited', read = 'read', execute = 'ran', search = 'searched' }
                  local action = kind_labels[msg.kind] or msg.kind or 'used'
                  table.insert(parts, '<tool>' .. action .. ' ' .. arg .. '</tool>')
                end
              end
            end
            local transcript = '<conversation>\n' .. table.concat(parts, '\n') .. '\n</conversation>'

            local prompt = 'Summarize this chat conversation in 5-8 words for use as a short title. '
              .. 'Reply with ONLY the title, no quotes, no punctuation at the end.\n\n'
              .. transcript

            local Async = require('utils.async')
            Async.void(function() ---@async
              local Shell = require('utils.shell')
              local title_progress = Spinner.create_progress_handle({
                group = 'Agentic',
                message = 'Generating title...',
                pattern = 'moon',
              })
              local max_retries = 3
              local title = nil
              for _ = 1, max_retries do
                local ok, output = Shell.async_cmd('agent', { '-pf', '--mode', 'ask', '--model', 'composer-2-fast' }, { stdin = prompt })
                if not ok or not output or #output == 0 then
                  Log.notify_error(table.concat(output or {}, '\n'), { title = 'Title generation failed, retrying...' })
                  goto continue
                end
                title = vim.trim(table.concat(output, ' '))
                local word_count = select(2, title:gsub('%S+', ''))
                if word_count <= 10 then
                  break
                end
                Log.notify_warn(string.format('Title too long (%d words), retrying...\n%s', word_count, title), { title = 'Title Generation' })
                ::continue::
              end
              if title and title ~= '' then
                title_progress:finish('Generated title')
              else
                title_progress:finish('Failed to generate title')
              end
              if title and title ~= '' then
                vim.schedule(function()
                  chat_history.title = title
                  chat_history:save()
                end)
              end
            end)
          end,
          ---@param data agentic.UserConfig.SessionUpdateData
          on_session_update = function(data)
            if not vim.api.nvim_tabpage_is_valid(data.tab_page_id) then
              return
            end
            local prev = vim.t[data.tab_page_id].agentic_usage
            if not prev or prev.session_id ~= data.session_id then
              vim.t[data.tab_page_id].agentic_usage = { session_id = data.session_id }
            end
            if data.update and data.update.sessionUpdate == 'usage_update' then
              local cost = data.update.cost and data.update.cost.amount or nil
              vim.t[data.tab_page_id].agentic_usage = {
                session_id = data.session_id,
                used = data.update.used,
                size = data.update.size,
                cost = cost,
              }
              local SessionRegistry = require('agentic.session_registry')
              local session = SessionRegistry.sessions[data.tab_page_id]
              local provider_name = session and session.agent and session.agent.provider_config and session.agent.provider_config.name or nil
              if cost and provider_name == 'Claude Agent ACP' then
                local sid = data.session_id
                local entry = _spend_by_session[sid]
                if not entry then
                  entry = { _prev = 0 }
                  _spend_by_session[sid] = entry
                end
                local prev = entry._prev or 0
                local delta = cost - prev
                local today = _utc_date()
                if delta > 1e-9 then
                  entry[today] = (entry[today] or 0) + delta
                elseif delta < -1e-9 then
                  -- Cost dropped (likely compaction/reset): count the new baseline once.
                  entry[today] = (entry[today] or 0) + cost
                end
                -- Always advance baseline so decreases/resets do not stall accrual.
                -- TODO: Handle rare upward-reset jumps (e.g. provider-side reindexing)
                -- by capping implausible single-update deltas.
                entry._prev = cost
                _flush_spend()
              end
            end
            local SessionRegistry = require('agentic.session_registry')
            local session = SessionRegistry.sessions and SessionRegistry.sessions[data.tab_page_id]
            if session then
              session:schedule_header_refresh()
            end
          end,
          on_file_edit = function(data)
            vim.api.nvim_exec_autocmds('User', {
              pattern = 'ChezmoiApplyPath',
              data = { path = data.file_path },
            })
          end,
        },
      })
    end,
  },
}
