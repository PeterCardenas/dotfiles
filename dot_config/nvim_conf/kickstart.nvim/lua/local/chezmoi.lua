local async = require('utils.async')

local chezmoi_augroup = vim.api.nvim_create_augroup('Chezmoi', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  callback = function(args)
    local bufnr = args.buf
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if not filepath:find('^' .. os.getenv('HOME') .. '/.local/share/chezmoi') then
      return
    end
    local shell = require('utils.shell')
    async.void(
      ---@async
      function()
        local success, output = shell.async_cmd('chezmoi', { 'apply', '--source-path', filepath })
        if not success then
          vim.schedule(function()
            vim.notify('chezmoi apply failed: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
          end)
          return
        end
      end
    )
  end,
  group = chezmoi_augroup,
  pattern = '*',
})

---@async
local function track_lazy_lock()
  local symlinked_lazy_lock_file_path = os.getenv('HOME') .. '/.config/nvim/lazy-lock.json'
  local shell = require('utils.shell')
  local success, output = shell.async_cmd('realpath', { symlinked_lazy_lock_file_path })
  if not success then
    vim.schedule(function()
      vim.notify('realpath failed: ' .. symlinked_lazy_lock_file_path, vim.log.levels.ERROR)
    end)
    return
  end
  local lazy_lock_file_path_unformatted = output[1]
  if not lazy_lock_file_path_unformatted then
    vim.schedule(function()
      vim.notify('lazy-lock.json not found' .. symlinked_lazy_lock_file_path, vim.log.levels.ERROR)
    end)
    return
  end

  local lazy_lock_file_path = lazy_lock_file_path_unformatted:gsub('\n', '')
  success, output = shell.async_cmd('chezmoi', { 'add', lazy_lock_file_path })
  if not success then
    vim.schedule(function()
      vim.notify('chezmoi add failed: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    end)
    return
  end
end

vim.api.nvim_create_autocmd('User', {
  callback = function()
    async.void(track_lazy_lock)
  end,
  group = chezmoi_augroup,
  pattern = { 'LazyInstall', 'LazyUpdate', 'LazyClean', 'LazyDone', 'LazyReload' },
})
