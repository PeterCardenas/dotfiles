local M = {}

local option = '@agentic_pending'
local timer
local enabled = true
local unpublished = {}
local tmux_published = unpublished
local herdr_published = unpublished
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

local function publish_tmux(value)
  if value == tmux_published then return true end
  local args = tmux_args(); if not args then return end
  vim.list_extend(args, { 'set-option', '-p', '-t', vim.env.TMUX_PANE })
  if value then vim.list_extend(args, { option, value }) else vim.list_extend(args, { '-u', option }) end
  local result = vim.system(vim.list_extend({ 'tmux' }, args)):wait(1000)
  if not result or result.code ~= 0 then return false end
  tmux_published = value
  return true
end

local function publish_herdr(state)
  if state == herdr_published then return true end
  if vim.env.HERDR_ENV ~= '1' or not vim.env.HERDR_PANE_ID then return end
  local herdr = vim.env.HERDR_BIN_PATH or 'herdr'
  local args
  if state then
    args = { herdr, 'pane', 'report-agent', vim.env.HERDR_PANE_ID, '--source', 'agentic.nvim', '--agent', 'agentic.nvim', '--state', state }
  else
    args = { herdr, 'pane', 'release-agent', vim.env.HERDR_PANE_ID, '--source', 'agentic.nvim', '--agent', 'agentic.nvim' }
  end
  if not state then
    local started = pcall(vim.system, args, { detach = true })
    if not started then return false end
    herdr_published = state
    return true
  end
  local started, process = pcall(vim.system, args)
  if not started then return false end
  local result = process:wait(1000)
  if not result or result.code ~= 0 then return false end
  herdr_published = state
  return true
end

function M.rename_workspace(title, tab_page_id, session_id)
  if type(title) ~= 'string' then return false end
  local workspace_title = vim.trim(vim.fn.strcharpart(vim.trim(title), 0, 20))
  if workspace_title == '' then return false end
  if vim.env.HERDR_ENV ~= '1' or not vim.env.HERDR_WORKSPACE_ID then return end
  if tab_page_id ~= vim.api.nvim_get_current_tabpage() then return end
  local registry = package.loaded['agentic.session_registry']
  local session = registry and registry.sessions and registry.sessions[tab_page_id]
  if not session or session.session_id ~= session_id then return end

  local herdr = vim.env.HERDR_BIN_PATH or 'herdr'
  local listed = vim.system({ herdr, 'worktree', 'list', '--workspace', vim.env.HERDR_WORKSPACE_ID }):wait(1000)
  if not listed or listed.code ~= 0 then return false end
  local ok, worktree_list = pcall(vim.json.decode, listed.stdout)
  if not ok then return false end
  local current_is_linked, has_sibling_workspace = false, false
  -- worktree list is scoped to the current repo; unopened checkouts are not workspace siblings.
  for _, worktree in ipairs(worktree_list.result and worktree_list.result.worktrees or {}) do
    if worktree.open_workspace_id == vim.env.HERDR_WORKSPACE_ID then
      current_is_linked = worktree.is_linked_worktree and not worktree.is_bare
    elseif worktree.open_workspace_id and not worktree.is_bare then
      has_sibling_workspace = true
    end
  end
  if not current_is_linked or not has_sibling_workspace then return false end
  local renamed = vim.system({ herdr, 'workspace', 'rename', vim.env.HERDR_WORKSPACE_ID, workspace_title }):wait(1000)
  return renamed and renamed.code == 0
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

-- A session only becomes actionable after a prompt from this tab's current session.
function M.tab_dots()
  local registry = package.loaded['agentic.session_registry']
  local sessions = registry and registry.sessions or {}
  local current = vim.api.nvim_get_current_tabpage()
  local dots = {}
  local default_hl = require('lualine.highlight').format_highlight('x', true)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local session = sessions[tab]
    local color = ''
    if type(session) == 'table' and type(session.session_id) == 'string' and prompted_sessions[tab] == session.session_id then
      color = session.is_generating and '%#DiagnosticOk#' or '%#DiagnosticError#'
    end
    dots[#dots + 1] = color .. (tab == current and '' or '') .. default_hl
  end
  return table.concat(dots, ' ')
end

function M.recompute()
  if not enabled then return end
  local working, idle = counts()
  local value = working + idle > 0 and ('v1:' .. owner() .. ':' .. working .. ':' .. idle) or nil
  publish_tmux(value)
  publish_herdr(working > 0 and 'working' or (idle > 0 and 'idle' or nil))
  vim.cmd.redrawstatus()
end

function M.clear()
  enabled = false
  if timer then timer:stop(); timer:close(); timer = nil end
  tmux_published = unpublished
  herdr_published = unpublished
  publish_tmux(nil)
  publish_herdr(nil)
end

local function start_timer()
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(M.recompute))
end

local function resume()
  enabled = true
  tmux_published = unpublished
  herdr_published = unpublished
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
