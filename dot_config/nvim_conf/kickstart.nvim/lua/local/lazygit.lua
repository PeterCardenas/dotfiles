local File = require('utils.file')
local Spinner = require('utils.spinner')

local M = {}

local function setup_lazygit_buffer()
  -- Ensure that the statuscolumn is removed correctly and the dropbar is rendered.
  require('statuscol')
  require('dropbar')
  vim.api.nvim_create_autocmd('TermOpen', {
    pattern = 'term://*lazygit*',
    once = true,
    callback = function(args)
      local dirty_buf_enter = false
      local bufnr = args.buf
      local function correct_size()
        local temp_bufnr = vim.api.nvim_create_buf(false, true)
        vim.cmd('resize 0 0')
        local cur_dirty_buf_enter = dirty_buf_enter
        vim.defer_fn(function()
          vim.cmd('resize 100 100')
          if not cur_dirty_buf_enter then
            dirty_buf_enter = true
            vim.api.nvim_set_current_buf(temp_bufnr)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_delete(temp_bufnr, { force = true })
            vim.cmd('startinsert')
          end
        end, 10)
        if dirty_buf_enter then
          dirty_buf_enter = false
        end
      end
      vim.keymap.set({ 't' }, 'q', function()
        local last_line_content = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]:gsub('^Fetching%s.%s', '')
        -- Don't navigate away when typing in new branch name or searching.
        if last_line_content:match('^Search:') or last_line_content:match('^Confirm:') or last_line_content:match('^Filter:') then
          vim.api.nvim_feedkeys('q', 'n', true)
          return
        end
        ---@type integer[]
        local bufnrs = vim
          .iter(vim.api.nvim_list_bufs())
          :filter(function(filtered_bufnr)
            return bufnr ~= filtered_bufnr and vim.fn.buflisted(filtered_bufnr) == 1
          end)
          :totable()
        table.sort(bufnrs, function(bufnr_a, bufnr_b)
          return vim.fn.getbufinfo(bufnr_a)[1].lastused > vim.fn.getbufinfo(bufnr_b)[1].lastused
        end)
        if #bufnrs == 0 then
          vim.notify('No other buffers found', vim.log.levels.ERROR)
          local alpha = require('alpha')
          alpha.start(false, alpha.default_config)
          return
        end
        vim.api.nvim_set_current_buf(bufnrs[1])
      end, { buffer = bufnr })
      vim.bo[bufnr].buflisted = false
      vim.api.nvim_create_autocmd('VimResized', {
        buffer = bufnr,
        callback = function()
          correct_size()
        end,
      })

      local function refresh_lazygit_files()
        -- TODO: consider shpool for backgrounding the process and sharing lazygit session
        local first_line_content = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
        ---@type string?
        local panel_content_title = first_line_content:match('╭─%[0%]─([a-zA-Z ]+)─')
        -- Command log doesn't have 0 keybinding to focus
        if not panel_content_title then
          panel_content_title = first_line_content:match('╭─([a-zA-Z ]+)─')
        end

        -- Focus the files panel, go to the top, and refresh it.
        vim.api.nvim_feedkeys('2<R', 't', false)
        -- Switch back to the panel before the files panel.
        local panel_content_title_to_keys = {
          ['Unstaged changes'] = '2',
          ['Log'] = '3',
          ['Remote'] = '3',
          ['Commit'] = '3',
          ['Patch'] = '4',
          ['Reflog Entry'] = '4',
          ['Stash'] = '5',
          ['Command log'] = '@j\r', -- Open command log picker, select focus and enter.
        }
        local panel_key = panel_content_title_to_keys[panel_content_title]
        if panel_key then
          vim.api.nvim_feedkeys(panel_key, 't', false)
          local buffer_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local cur_panel_index ---@type integer?
          local panel_to_selected_indices = {} ---@type table<integer, integer>
          for _, line in ipairs(buffer_content) do
            local current_index_str = line:match('^╭─%[(%d)%]─')
            if current_index_str then
              cur_panel_index = tonumber(current_index_str)
            elseif cur_panel_index then
              local current_index = line:match('^╰─[^0-9]+(%d+) of %d+─╯')
              if current_index then
                panel_to_selected_indices[cur_panel_index] = tonumber(current_index)
                cur_panel_index = nil
                -- Only go back to selected index for file panel (first panel)
                break
              end
            end
          end
          if next(panel_to_selected_indices) then
            for panel_index, _ in pairs(panel_to_selected_indices) do
              vim.api.nvim_feedkeys(panel_index .. '<', 't', false)
            end
            for panel_index, selected_index in pairs(panel_to_selected_indices) do
              vim.api.nvim_feedkeys(tostring(panel_index), 't', false)
              local input = string.rep('j', selected_index - 1)
              vim.api.nvim_feedkeys(input, 't', false)
              -- Preview window doesn't update sometimes, so switch between previous and current to force update.
              vim.api.nvim_feedkeys('kj', 't', false)
            end
            vim.api.nvim_feedkeys(panel_key, 't', false)
          end
        end
      end

      ---@type SpinnerTimer?
      local donate_timer

      local function stop_refresh_timer()
        if donate_timer then
          donate_timer.stop()
          donate_timer = nil
        end
      end

      local function start_refresh_timer()
        stop_refresh_timer()
        donate_timer = Spinner.create_timer()
        donate_timer.start(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            stop_refresh_timer()
            return
          end
          local last_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1] or ''
          if last_line:match('Donate') then
            stop_refresh_timer()
            refresh_lazygit_files()
          end
        end)
      end

      vim.api.nvim_create_autocmd('BufEnter', {
        buffer = bufnr,
        callback = function()
          vim.cmd('startinsert')
          if not dirty_buf_enter then
            start_refresh_timer()
          else
            stop_refresh_timer()
            dirty_buf_enter = false
          end
        end,
      })
    end,
  })
end

function M.open_lazygit()
  local bufnrs = vim.api.nvim_list_bufs()
  local lazygit_bufnr = vim.tbl_filter(function(bufnr) ---@param bufnr integer
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    return bufname:match('term://.*lazygit %-%-path ' .. File.get_git_root():gsub('%-', '%%-'))
  end, bufnrs)[1]
  if lazygit_bufnr ~= nil then
    local bufinfo = vim.fn.getbufinfo(lazygit_bufnr)[1]
    if bufinfo.loaded == 0 then
      setup_lazygit_buffer()
    end
    vim.api.nvim_set_current_buf(lazygit_bufnr)
    return
  end
  setup_lazygit_buffer()
  vim.cmd('term lazygit --path ' .. File.get_git_root())
end

function M.set_keymap()
  local nmap = require('utils.keymap').nmap
  nmap('Open LazyGit in buffer', 'gg', M.open_lazygit)
  -- Close the lazygit buffer when exiting Neovim.
  -- When restoring a session the lazygit buffer isn't created correctly.
  vim.api.nvim_create_autocmd('BufAdd', {
    pattern = '*COMMIT_EDITMSG',
    callback = function(args)
      ---@type integer
      local commit_bufnr = args.buf
      vim.cmd('startinsert')
      ---@return integer?
      local function get_lazygit_bufnr()
        return vim.iter(vim.api.nvim_list_bufs()):find(function(bufnr) ---@param bufnr integer
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          return bufname:match('term://.*lazygit')
        end)
      end
      if get_lazygit_bufnr() ~= nil then
        vim.keymap.set('n', '<leader>q', function()
          local lazygit_bufnr = get_lazygit_bufnr()
          if lazygit_bufnr ~= nil then
            vim.api.nvim_set_current_buf(lazygit_bufnr)
          end
          require('bufdelete').bufdelete(commit_bufnr)
        end, { buffer = commit_bufnr })
      end
    end,
  })
end

return M
