local Async = require('utils.async')
local Shell = require('utils.shell')
local Log = require('utils.log')
local File = require('utils.file')
local Spinner = require('utils.spinner')

local chezmoi_augroup = vim.api.nvim_create_augroup('Chezmoi', { clear = true })

---@param path any
---@return string?
local function parse_file_path(path)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local file_path = vim.fn.expand(path)
  if not vim.startswith(file_path, '/') then
    file_path = File.get_cwd() .. '/' .. file_path
  end
  if File.file_exists(file_path) or vim.fn.isdirectory(file_path) == 1 then
    return file_path
  end
  return nil
end

---Returns true if the file at `filepath` might need to be synced with chezmoi.
---@param source_path string
---@param filepath string
---@return boolean
local function maybe_should_sync(source_path, filepath)
  if not vim.startswith(filepath, source_path) then
    return false
  end
  local relative_filepath = filepath:sub(#source_path + 2)
  if relative_filepath:match('^%.git') then
    return false
  end
  if relative_filepath:match('^%.chezmoitemplates/') then
    return true
  end
  if relative_filepath:match('^%.chezmoi') then
    return false
  end
  return true
end

---@async
---Returns whether the apply errored and the error logs if errored.
---@param source_path string
---@param filepath string
---@return boolean, string[]
local function apply_filepath(source_path, filepath)
  if not maybe_should_sync(source_path, filepath) then
    return false, {}
  end
  local relative_filepath = filepath:sub(#source_path + 2)
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
  if not maybe_should_sync(source_path, filepath) then
    return
  end
  local progress_handle = Spinner.create_progress_handle({
    group = 'Chezmoi',
    message = 'Applying changes with chezmoi...',
  })
  local errored, logs = apply_filepath(source_path, filepath)
  if errored then
    progress_handle:finish('chezmoi apply failed')
    Log.notify_error('chezmoi apply failed: ' .. table.concat(logs, '\n'))
    return
  end
  progress_handle:finish('Applied changes with chezmoi')
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
      local file_path = args.data and args.data.path
      file_path = parse_file_path(file_path)
      if not file_path then
        return
      end
      Async.void(function() ---@async
        apply_and_notify(source_path, file_path)
      end)
    end,
    group = chezmoi_augroup,
    pattern = 'ChezmoiApplyPath',
  })
end

return M
