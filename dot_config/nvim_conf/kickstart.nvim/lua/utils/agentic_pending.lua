local M = {}

local option = '@agentic_pending'
local timer
local enabled = true
local unpublished = {}
local published = unpublished
local prompted_sessions = {}

local function tmux_args()
  if not vim.env.TMUX or not vim.env.TMUX_PANE then return nil end
  local socket = vim.split(vim.env.TMUX, ',', { plain = true })[1]
  return socket:find('/', 1, true) and { '-S', socket } or { '-L', socket }
end

local function owner()
  local pid = vim.fn.getpid()
  local file = io.open('/proc/' .. pid .. '/stat', 'r')
  if not file then return tostring(pid) .. ':0' end
  local contents = file:read('*a'); file:close()
  local rest = contents:match('^%d+ %b() (.*)$')
  local fields = rest and vim.split(rest, '%s+', { trimempty = true })
  return tostring(pid) .. ':' .. (fields and fields[20] or '0')
end

local function publish(value)
  if value == published then return true end
  local args = tmux_args(); if not args then return end
  vim.list_extend(args, { 'set-option', '-p', '-t', vim.env.TMUX_PANE })
  if value then vim.list_extend(args, { option, value }) else vim.list_extend(args, { '-u', option }) end
  local result = vim.system(vim.list_extend({ 'tmux' }, args)):wait(1000)
  if not result or result.code ~= 0 then return false end
  published = value
  return true
end

function M.mark_prompt(data)
  if type(data) ~= 'table' or type(data.session_id) ~= 'string' then return end
  local registry = package.loaded['agentic.session_registry']
  local session = registry and registry.sessions and registry.sessions[data.tab_page_id]
  -- The hook plus matching session identity proves this came from a user submission; prompt text may be empty.
  if type(session) == 'table' and session.session_id == data.session_id then
    prompted_sessions[data.tab_page_id] = data.session_id
    M.recompute()
  end
end

local function counts()
  local registry = package.loaded['agentic.session_registry']
  if not registry or not registry.sessions then return 0, 0 end
  local working, idle = 0, 0
  for tab, session_id in pairs(prompted_sessions) do
    local session = registry.sessions[tab]
    if not vim.api.nvim_tabpage_is_valid(tab) or type(session) ~= 'table' or session.session_id ~= session_id then
      prompted_sessions[tab] = nil
    end
  end
  for tab, session in pairs(registry.sessions) do
    if vim.api.nvim_tabpage_is_valid(tab) and type(session) == 'table' then
      local id = session.session_id
      if type(id) == 'string' and prompted_sessions[tab] == id then
        if session.is_generating then working = working + 1 else idle = idle + 1 end
      end
    end
  end
  return working, idle
end

function M.recompute()
  if not enabled or not tmux_args() then return end
  local working, idle = counts()
  local value = working + idle > 0 and ('v1:' .. owner() .. ':' .. working .. ':' .. idle) or nil
  publish(value)
end

function M.clear()
  enabled = false
  if timer then timer:stop(); timer:close(); timer = nil end
  published = unpublished
  publish(nil)
end

local function start_timer()
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(M.recompute))
end

local function resume()
  enabled = true
  published = unpublished
  start_timer()
  M.recompute()
end

function M.setup()
  local group = vim.api.nvim_create_augroup('agentic_pending_publisher', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimSuspend', 'VimLeavePre' }, { group = group, callback = M.clear })
  vim.api.nvim_create_autocmd('VimResume', { group = group, callback = resume })
  start_timer()
  M.recompute()
end

return M
