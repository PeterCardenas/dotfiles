---@class ConfigStaleness
local M = {}

local function canonical(path)
  return vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ':p'):gsub('/+$', '')
end

local config_root = canonical(vim.fn.stdpath('config'))
---@type table<string, { sec: integer, nsec: integer, size: integer }>
local snapshots = {}
local stale = false
local timer = vim.uv.new_timer()

---@param path string
---@return boolean
local function is_config_path(path)
  return path == config_root or vim.startswith(path, config_root .. '/')
end

---@param path string
---@return { sec: integer, nsec: integer, size: integer }?
local function snapshot(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  return { sec = stat.mtime.sec, nsec = stat.mtime.nsec, size = stat.size }
end

---@return string[]
local function loaded_config_files()
  local files = {}
  for _, script in ipairs(vim.fn.getscriptinfo()) do
    local path = script.name
    if path then
      path = canonical(path)
      if is_config_path(path) and path:sub(-4) == '.lua' then
        table.insert(files, path)
      end
    end
  end
  return files
end

local function mark_stale()
  if stale then
    return
  end
  stale = true
  local lualine = package.loaded.lualine
  if lualine then
    lualine.refresh({ scope = 'window' })
  end
end

local function check()
  local paths = loaded_config_files()
  for path in pairs(snapshots) do
    table.insert(paths, path)
  end
  for _, path in ipairs(paths) do
    local current = snapshot(path)
    local previous = snapshots[path]
    if not previous then
      snapshots[path] = current
    elseif not current or current.sec ~= previous.sec or current.nsec ~= previous.nsec or current.size ~= previous.size then
      mark_stale()
    end
  end
end

M.check = check

---@return boolean
function M.is_stale()
  return stale
end

---@return string
function M.component()
  return stale and '' or ''
end

for _, path in ipairs(loaded_config_files()) do
  snapshots[path] = snapshot(path)
end

timer:start(1000, 1000, vim.schedule_wrap(check))
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end,
})

return M
