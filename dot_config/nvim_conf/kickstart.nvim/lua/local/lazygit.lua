local M = {}

local function setup_lazygit_buffer()
  -- Ensure that the statuscolumn is removed correctly and the dropbar is rendered.
  require('statuscol')
  require('dropbar')
  vim.api.nvim_create_autocmd('TermOpen', {
    pattern = 'term://*lazygit',
    once = true,
    callback = function(args)
      local bufnr = args.buf
      local function correct_size()
        vim.cmd('resize 0 0')
        vim.defer_fn(function()
          vim.cmd('resize 100 100')
        end, 50)
      end
      vim.cmd('startinsert')
      vim.keymap.set({ 't' }, 'q', function()
        local bufnrs = vim
          .iter(vim.api.nvim_list_bufs())
          :filter(function(filtered_bufnr)
            return not vim.api.nvim_buf_get_name(filtered_bufnr):match('term://.*lazygit') and vim.fn.buflisted(filtered_bufnr) == 1
          end)
          :totable()
        table.sort(bufnrs, function(bufnr_a, bufnr_b)
          return vim.fn.getbufinfo(bufnr_a)[1].lastused > vim.fn.getbufinfo(bufnr_b)[1].lastused
        end)
        if #bufnrs == 0 then
          vim.notify('No other buffers found', vim.log.levels.ERROR)
          require('plugins.telescope.setup').find_files(false)
          return
        end
        vim.api.nvim_set_current_buf(bufnrs[1])
      end, { buffer = bufnr })
      vim.api.nvim_buf_set_option(bufnr, 'number', false)
      vim.api.nvim_buf_set_option(bufnr, 'foldcolumn', '0')
      vim.api.nvim_buf_set_option(bufnr, 'statuscolumn', '')
      vim.api.nvim_create_autocmd('VimResized', {
        buffer = bufnr,
        callback = function()
          correct_size()
        end,
      })
      vim.api.nvim_create_autocmd('BufEnter', {
        buffer = bufnr,
        callback = function()
          vim.cmd('startinsert')
          -- Focus the files panel and refresh it.
          -- TODO: Wait for the lazygit UI to render before refreshing.
          vim.api.nvim_feedkeys('2R', 't', false)
          correct_size()
        end,
      })
    end,
  })
end

function M.open_lazygit()
  local bufnrs = vim.api.nvim_list_bufs()
  local lazygit_bufnr = vim.tbl_filter(function(bufnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    return bufname:match('term://.*lazygit')
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
  -- TODO: Open term in a persistent buffer in a floating window instead.
  vim.cmd('term lazygit')
end

function M.set_keymap()
  local nmap = require('utils.keymap').nmap
  nmap('Open LazyGit in buffer', 'gg', M.open_lazygit)
  -- Close the lazygit buffer when exiting Neovim.
  -- When restoring a session the lazygit buffer isn't created correctly.
  -- TODO causes neovim to hang when exiting.
  -- vim.api.nvim_create_autocmd('VimLeavePre', {
  --   callback = function()
  --     local lazygit_bufnr = vim.iter(vim.api.nvim_list_bufs()):find(function(bufnr) ---@param bufnr integer
  --       local bufname = vim.api.nvim_buf_get_name(bufnr)
  --       return bufname:match('term://.*lazygit')
  --     end)
  --     if lazygit_bufnr ~= nil then
  --       require('bufdelete').bufdelete(lazygit_bufnr)
  --     end
  --   end,
  -- })
  vim.api.nvim_create_autocmd('BufAdd', {
    pattern = '*COMMIT_EDITMSG',
    callback = function(args)
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
