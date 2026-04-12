local Async = require('utils.async')
local Shell = require('utils.shell')
local Log = require('utils.log')

local chezmoi_augroup = vim.api.nvim_create_augroup('Chezmoi', { clear = true })

---@async
---Returns whether the apply errored and the error logs if errored.
---@param source_path string
---@param filepath string
---@return boolean, string[]
local function apply_filepath(source_path, filepath)
  if not vim.startswith(filepath, source_path) then
    return false, {}
  end
  local relative_filepath = filepath:sub(#source_path + 2)
  -- Ignore files that should never be applied
  if relative_filepath:match('^%.git') then
    return false, {}
  end
  -- Template files can't be applied directly — find and apply their dependents
  local template_name = relative_filepath:match('^%.chezmoitemplates/(.+)$')
  if template_name then
    local found, dependents = Shell.async_cmd('rg', { '-l', '(include|template) "' .. template_name .. '"', source_path })
    if found then
      for _, dependent in ipairs(dependents) do
        local apply_ok, apply_output = Shell.async_cmd('chezmoi', { '--source', source_path, 'apply', '--source-path', dependent })
        if not apply_ok or #apply_output > 0 then
          return true, apply_output
        end
      end
    end
    return false, {}
  end
  if relative_filepath:match('^%.chezmoi') then
    return false, {}
  end
  -- Do not apply ignored files.
  local success, output = Shell.async_cmd('chezmoi', { '--source', source_path, 'ignored' })
  if success and vim.tbl_contains(output, relative_filepath) then
    return false, {}
  end
  success, output = Shell.async_cmd('chezmoi', { '--source', source_path, 'target-path', filepath })
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

  success, output = Shell.async_cmd('chezmoi', { '--source', source_path, 'apply', '--source-path', filepath })
  if not success or #output > 0 then
    return true, output
  end
  return false, {}
end

---@async
local function track_lazy_lock()
  local symlinked_lazy_lock_file_path = os.getenv('HOME') .. '/.config/nvim/lazy-lock.json'
  local success, output = Shell.async_cmd('realpath', { symlinked_lazy_lock_file_path })
  if not success then
    Log.notify_error('realpath failed: ' .. symlinked_lazy_lock_file_path)
    return
  end
  local lazy_lock_file_path_unformatted = output[1]
  if not lazy_lock_file_path_unformatted then
    Log.notify_error('lazy-lock.json not found' .. symlinked_lazy_lock_file_path)
    return
  end

  local lazy_lock_file_path = lazy_lock_file_path_unformatted:gsub('\n', '')
  success, output = Shell.async_cmd('chezmoi', { 'add', lazy_lock_file_path })
  if not success then
    Log.notify_error('chezmoi add failed: ' .. table.concat(output, '\n'))
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

local M = {}

---@async
---@param source_path string
---@param filepath string
local function apply_and_notify(source_path, filepath)
  local notify_key = 'chezmoi_apply_' .. source_path
  require('fidget').notify(' ', vim.log.levels.WARN, {
    group = notify_key,
    key = notify_key,
    annote = 'Applying changes with chezmoi...',
    ttl = math.huge,
  })
  local errored, logs = apply_filepath(source_path, filepath)
  -- HACK: Fidget does not handle immediate removal of notifications, so sleep for a bit
  Shell.sleep(100)
  require('fidget').notification.remove(notify_key, notify_key)
  if errored then
    Log.notify_error('chezmoi apply failed: ' .. table.concat(logs, '\n'))
  end
end

---@param source_path string
function M.setup(source_path)
  vim.api.nvim_create_autocmd('BufWritePost', {
    callback = function(args)
      local filepath = vim.api.nvim_buf_get_name(args.buf)
      Async.void(function() ---@async
        apply_and_notify(source_path, filepath)
      end)
    end,
    group = chezmoi_augroup,
    pattern = '*',
  })

  vim.api.nvim_create_autocmd('User', {
    callback = function(args)
      local filepath = args.data and args.data.file_path
      if not filepath or type(filepath) ~= 'string' or not vim.startswith(filepath, '/') then
        Log.notify_error('Invalid params for ChezmoiApplyFile: ' .. vim.inspect(args.data))
        return
      end
      Async.void(function() ---@async
        apply_and_notify(source_path, filepath)
      end)
    end,
    group = chezmoi_augroup,
    pattern = 'ChezmoiApplyFile',
  })
end

return M
