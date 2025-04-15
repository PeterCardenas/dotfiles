local Async = require('utils.async')
local Shell = require('utils.shell')

local chezmoi_augroup = vim.api.nvim_create_augroup('Chezmoi', { clear = true })

---@async
---Returns whether the apply errored and the error logs if errored.
---@param filepath string
---@return boolean, string[]
local function apply_filepath(filepath)
  local chezmoi_root = os.getenv('HOME') .. '/.local/share/chezmoi/'
  if not filepath:find('^' .. chezmoi_root) then
    return false, {}
  end
  local relative_filepath = filepath:sub(#chezmoi_root + 1)
  -- Ignore files that should never be applied
  if relative_filepath:match('^%.git') or relative_filepath:match('^%.chezmoi') then
    return false, {}
  end
  -- Do not apply ignored files.
  local success, output = Shell.async_cmd('chezmoi', { 'ignored' })
  if success and vim.tbl_contains(output, relative_filepath) then
    return false, {}
  end
  success, output = Shell.async_cmd('chezmoi', { 'target-path', filepath })
  if not success then
    return true, output
  end
  local target_filepath = output[1]
  if vim.fn.filereadable(target_filepath) == 0 then
    local parent_dir = vim.fn.fnamemodify(target_filepath, ':h')
    if vim.fn.isdirectory(parent_dir) == 0 then
      success, output = Shell.async_cmd('mkdir', { '-p', parent_dir })
      if not success then
        return true, output
      end
    end
  end

  success, output = Shell.async_cmd('chezmoi', { 'apply', '--source-path', filepath })
  if not success then
    return true, output
  end
  return false, {}
end

vim.api.nvim_create_autocmd('BufWritePost', {
  callback = function(args)
    ---@type integer
    local bufnr = args.buf
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    Async.void(
      ---@async
      function()
        require('fidget').notify('Applying changes with chezmoi...', vim.log.levels.INFO, {
          group = 'chezmoi_apply',
          key = 'chezmoi_apply',
          annote = '',
        })
        local errored, logs = apply_filepath(filepath)
        require('fidget').notification.remove('chezmoi_apply', 'chezmoi_apply')
        if errored then
          vim.schedule(function()
            vim.notify('chezmoi apply failed: ' .. table.concat(logs, '\n'), vim.log.levels.ERROR)
          end)
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
  local success, output = Shell.async_cmd('realpath', { symlinked_lazy_lock_file_path })
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
  success, output = Shell.async_cmd('chezmoi', { 'add', lazy_lock_file_path })
  if not success then
    vim.schedule(function()
      vim.notify('chezmoi add failed: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    end)
    return
  end
end

vim.api.nvim_create_autocmd('User', {
  callback = function()
    Async.void(track_lazy_lock)
  end,
  group = chezmoi_augroup,
  pattern = { 'LazyInstall', 'LazyUpdate', 'LazyClean', 'LazyDone', 'LazyReload' },
})
