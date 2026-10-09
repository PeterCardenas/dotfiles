local M = {}

local option = '@agentic_pending'
local timer
local enabled = true
local unpublished = {}
local tmux_published = unpublished
local herdr_confirmed
local herdr_desired
local herdr_in_flight = false
local herdr_reported = false
local herdr_generation = 0
local herdr_sequence = vim.uv.hrtime()
local prompted_sessions = {}

local function tmux_args()
  if not vim.env.TMUX or not vim.env.TMUX_PANE then return nil end
  local socket = vim.split(vim.env.TMUX, ',', { plain = true })[1]
  return socket:find('/', 1, true) and { '-S', socket } or { '-L', socket }
end

local process_owner
local function owner()
  if process_owner then return process_owner end
  local pid = vim.fn.getpid()
  local token = vim.fn.system({ 'process-start-token', tostring(pid) }):gsub('%s+', '')
  -- Keep the Herdr source unique if ps is unavailable; tmux rejects unverifiable markers.
  if vim.v.shell_error ~= 0 or not token:match('^[A-Za-z0-9]+$') then
    token = tostring(vim.uv.hrtime())
  end
  process_owner = tostring(pid) .. ':' .. token
  return process_owner
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

local herdr_source = 'agentic.nvim:' .. owner()

local function herdr_args(state)
  -- Sequences prevent a delayed release from undoing a newer report from this process.
  herdr_sequence = math.max(herdr_sequence + 1, vim.uv.hrtime())
  local args = { vim.env.HERDR_BIN_PATH or 'herdr', 'pane', state and 'report-agent' or 'release-agent', vim.env.HERDR_PANE_ID, '--source', herdr_source, '--agent', 'agentic.nvim' }
  if state then vim.list_extend(args, { '--state', state }) end
  vim.list_extend(args, { '--seq', string.format('%.0f', herdr_sequence) })
  return args
end

local function flush_herdr()
  if herdr_in_flight or herdr_desired == herdr_confirmed then return end
  local state = herdr_desired
  local generation = herdr_generation
  herdr_in_flight = true
  local started = pcall(vim.system, herdr_args(state), {}, vim.schedule_wrap(function(result)
    if generation ~= herdr_generation then return end
    herdr_in_flight = false
    if result.code ~= 0 then return end -- The next timer tick retries without spinning.
    herdr_confirmed = state
    herdr_reported = state ~= nil
    if herdr_desired ~= state then flush_herdr() end
  end))
  if not started then herdr_in_flight = false; return end
  if state then herdr_reported = true end
end

local function publish_herdr(state)
  if vim.env.HERDR_ENV ~= '1' or not vim.env.HERDR_PANE_ID then return end
  herdr_desired = state
  flush_herdr()
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
  local listed = vim.system({ herdr, 'workspace', 'list' }):wait(1000)
  if not listed or listed.code ~= 0 then return false end
  local ok, workspace_list = pcall(vim.json.decode, listed.stdout)
  if not ok or type(workspace_list) ~= 'table' then return false end
  local workspaces = workspace_list.result and workspace_list.result.workspaces or {}
  local repo_key
  for _, workspace in ipairs(workspaces) do
    if workspace.workspace_id == vim.env.HERDR_WORKSPACE_ID then
      local worktree = workspace.worktree
      if not worktree or not worktree.is_linked_worktree then return false end
      repo_key = worktree.repo_key
      break
    end
  end
  if not repo_key then return false end
  -- A checkout can be open without belonging to a sidebar group; require its base workspace.
  local has_base = false
  for _, workspace in ipairs(workspaces) do
    local worktree = workspace.worktree
    if workspace.workspace_id ~= vim.env.HERDR_WORKSPACE_ID and worktree and worktree.repo_key == repo_key and worktree.is_linked_worktree == false then
      has_base = true
      break
    end
  end
  if not has_base then return false end
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
      color = session.is_generating and '%#AgenticTabWorking#' or '%#AgenticTabIdle#'
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
  publish_tmux(nil)
  herdr_generation = herdr_generation + 1
  herdr_in_flight = false
  herdr_confirmed = nil
  herdr_desired = nil
  if herdr_reported and vim.env.HERDR_ENV == '1' and vim.env.HERDR_PANE_ID then
    pcall(vim.system, herdr_args(nil), { detach = true })
    herdr_reported = false
  end
end

local function start_timer()
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(M.recompute))
end

local function resume()
  enabled = true
  tmux_published = unpublished
  herdr_confirmed = nil
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
