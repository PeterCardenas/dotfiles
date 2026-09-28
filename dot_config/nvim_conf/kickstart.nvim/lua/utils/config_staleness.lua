---@class ConfigStaleness
local M = {}

local config_root = vim.uv.fs_realpath(vim.fn.stdpath('config')) or vim.fn.stdpath('config')
---@type table<string, { sec: integer, nsec: integer, size: integer }>
local snapshots = {}
local stale = false
local timer = vim.uv.new_timer()

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
local function config_files()
  -- Lazy loads plugin specs with loadfile(), which getscriptinfo() does not record.
  return vim.fs.find(function(name)
    return name:sub(-4) == '.lua'
  end, { path = config_root, type = 'file', limit = math.huge })
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
  for _, path in ipairs(config_files()) do
    local current = snapshot(path)
    local previous = snapshots[path]
    if not previous or not current or current.sec ~= previous.sec or current.nsec ~= previous.nsec or current.size ~= previous.size then
      mark_stale()
      return
    end
  end
  for path in pairs(snapshots) do
    if not snapshot(path) then
      mark_stale()
      return
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

for _, path in ipairs(config_files()) do
  snapshots[path] = snapshot(path)
end

timer:start(10000, 10000, vim.schedule_wrap(check))
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end,
})

return M
