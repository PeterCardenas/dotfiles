package.path = 'dot_config/nvim_conf/kickstart.nvim/lua/?.lua;' .. package.path

local Async = require('utils.async')
local completed = false
Async.run(function() ---@async
local Context = require('utils.workspace_context')
local template = '<conversation>session context</conversation>'
local inserted = Context.insert(template, 'diff literal %1')
assert(inserted:find('diff literal %1', 1, true), inserted)
local retried = Context.retry(inserted, 'A name much too long')
assert(retried:find('diff literal %1', 1, true), retried)
assert(retried:find('session context', 1, true), retried)
local root = vim.fn.tempname()
local function git(args, cwd)
  local result = vim.system(vim.list_extend({ 'git' }, args), { cwd = cwd }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local function write(path, text)
  local file = assert(io.open(path, 'w'))
  file:write(text)
  file:close()
end
local function repo(name, default_branch, remote)
  local path = root .. '/' .. name
  vim.fn.mkdir(path, 'p')
  git({ 'init', '-b', default_branch }, path)
  git({ 'config', 'user.name', 'Workspace Test' }, path)
  git({ 'config', 'user.email', 'workspace-test@example.invalid' }, path)
  write(path .. '/plan.txt', 'base\n')
  git({ 'add', 'plan.txt' }, path)
  git({ 'commit', '-m', 'base' }, path)
  git({ 'checkout', '-b', 'feature/' .. name }, path)
  write(path .. '/plan.txt', name .. ' intent\n')
  git({ 'add', 'plan.txt' }, path)
  git({ 'commit', '-m', 'intent' }, path)
  local bare = root .. '/' .. name .. '.git'
  git({ 'init', '--bare', '-b', default_branch, bare }, root)
  git({ 'remote', 'add', remote, bare }, path)
  git({ 'push', '-u', remote, default_branch }, path)
  git({ 'push', remote, 'feature/' .. name }, path)
  git({ 'remote', 'set-head', remote, default_branch }, path)
  git({ 'reset', '--hard', remote .. '/feature/' .. name }, path)
  return path
end

vim.fn.mkdir(root, 'p')
local cache = repo('cache', 'trunk', 'upstream')
local linked = root .. '/cache-linked'
git({ 'worktree', 'add', '-b', 'feature/linked', linked }, cache)
assert(Context.is_linked_worktree(linked), 'linked worktree should be recognized')
assert(not Context.is_linked_worktree(cache), 'base checkout should not be recognized as linked')
write(cache .. '/plan.txt', 'cache %1 working tree hunk\n')
local context = Context.build(cache)
assert(context:find('Branch: feature/cache', 1, true), context)
assert(context:find('Default branch: upstream/trunk', 1, true), context)
assert(context:find('cache %1 working tree hunk', 1, true), context)
local main_fallback = repo('mainfallback', 'main', 'upstream')
git({ 'remote', 'set-head', '--delete', 'upstream' }, main_fallback)
local fallback_remote = Context.build(main_fallback)
assert(fallback_remote:find('Default branch: upstream/main', 1, true), fallback_remote)

local local_default = root .. '/local-default'
vim.fn.mkdir(local_default, 'p')
git({ 'init', '-b', 'main' }, local_default)
git({ 'config', 'user.name', 'Workspace Test' }, local_default)
git({ 'config', 'user.email', 'workspace-test@example.invalid' }, local_default)
write(local_default .. '/plan.txt', 'base\n')
git({ 'add', 'plan.txt' }, local_default)
git({ 'commit', '-m', 'base' }, local_default)
git({ 'checkout', '-b', 'feature/local' }, local_default)
write(local_default .. '/plan.txt', 'local default fallback hunk\n')
local local_context = Context.build(local_default)
assert(local_context:find('Default branch: main', 1, true), local_context)
assert(local_context:find('local default fallback hunk', 1, true), local_context)

local long = repo('truncation', 'main', 'origin')
write(long .. '/plan.txt', string.rep('bounded diff content\n', 2000))
local bounded = Context.build(long)
assert(#bounded <= 12200, #bounded)
assert(bounded:find('[diff truncated]', 1, true), 'diff should be truncated')

local secrets = repo('secrets', 'main', 'origin')
write(secrets .. '/.env.local', 'API_TOKEN=do-not-send\n')
git({ 'add', '.env.local' }, secrets)
git({ 'commit', '-m', 'fixture env file' }, secrets)
git({ 'push', 'origin', 'feature/secrets' }, secrets)
git({ 'push', 'origin', 'main' }, secrets)
write(secrets .. '/.env.local', 'API_TOKEN=fixture-secret-value\n')
local safe_context = Context.build(secrets)
assert(not safe_context:find('fixture-secret-value', 1, true), safe_context)

local empty = repo('empty', 'main', 'origin')
git({ 'checkout', '-B', 'feature/empty', 'origin/main' }, empty)
local empty_context = Context.build(empty)
assert(empty_context:find('Branch: feature/empty', 1, true), empty_context)
assert(not empty_context:find('Diff against default branch:', 1, true), empty_context)

local orphan = root .. '/orphan'
vim.fn.mkdir(orphan, 'p')
git({ 'init', '-b', 'feature/orphan' }, orphan)
git({ 'config', 'user.name', 'Workspace Test' }, orphan)
git({ 'config', 'user.email', 'workspace-test@example.invalid' }, orphan)
write(orphan .. '/plan.txt', 'orphan work\n')
git({ 'add', 'plan.txt' }, orphan)
git({ 'commit', '-m', 'orphan' }, orphan)
local orphan_context = Context.build(orphan)
assert(orphan_context:find('Branch: feature/orphan', 1, true), orphan_context)

local no_git = Context.build(root)
assert(no_git == '', no_git)

local original_system = vim.system
local snapshot_delay = 0
local git_callback_delay = 0
local snapshot_calls = 0
local original_cwd = vim.uv.cwd()
local original_herdr_env = vim.env.HERDR_ENV
local original_workspace_id = vim.env.HERDR_WORKSPACE_ID
local original_pane_id = vim.env.HERDR_PANE_ID
local original_bin_path = vim.env.HERDR_BIN_PATH
local current_snapshot
local rename_calls = {}
vim.system = function(command, opts, on_exit)
  if command[1] == 'herdr' then
    local result
    if command[2] == 'api' and command[3] == 'snapshot' then
      snapshot_calls = snapshot_calls + 1
      result = { code = 0, stdout = vim.json.encode({ result = { snapshot = current_snapshot } }), stderr = '' }
    elseif command[2] == 'workspace' and command[3] == 'rename' then
      rename_calls[#rename_calls + 1] = { workspace_id = command[4], title = command[5] }
      result = { code = 0, stdout = '', stderr = '' }
    else
      error('unexpected Herdr command: ' .. vim.inspect(command))
    end
    vim.defer_fn(function()
      if opts.stdout then opts.stdout(nil, result.stdout); opts.stdout(nil, nil) end
      if opts.stderr then opts.stderr(nil, result.stderr); opts.stderr(nil, nil) end
      on_exit(result)
    end, snapshot_delay)
    return { kill = function() end }
  end
  if git_callback_delay > 0 and command[1] == 'git' then
    return original_system(command, opts, function(result)
      vim.defer_fn(function() on_exit(result) end, git_callback_delay)
    end)
  end
  return original_system(command, opts, on_exit)
end
local function snapshot(workspaces, pane_workspace_id)
  current_snapshot = {
    workspaces = workspaces,
    panes = { { pane_id = 'w3:p1', workspace_id = pane_workspace_id or 'linked' } },
  }
end
local base_root = git({ 'rev-parse', '--show-toplevel' }, cache):gsub('\n', '')
local common_dir = git({ 'rev-parse', '--path-format=absolute', '--git-common-dir' }, linked):gsub('\n', '')
local workspaces = {
  { workspace_id = 'base', worktree = { checkout_path = base_root, repo_key = common_dir, is_linked_worktree = false } },
  { workspace_id = 'linked', worktree = { checkout_path = linked, repo_key = common_dir, is_linked_worktree = true } },
}
local registry = { sessions = { [vim.api.nvim_get_current_tabpage()] = { session_id = 'active' } } }
package.loaded['agentic.session_registry'] = registry
vim.env.HERDR_ENV = '1'
vim.env.HERDR_PANE_ID = 'w3:p1'
vim.env.HERDR_BIN_PATH = 'herdr'
vim.env.HERDR_WORKSPACE_ID = 'base'
vim.cmd('cd ' .. vim.fn.fnameescape(linked))
snapshot(workspaces, 'base')
local Pending = require('utils.agentic_pending')
local await_rename = Async.wrap(function(title, tab_page_id, session_id, done)
  Pending.rename_workspace(title, tab_page_id, session_id, done)
end, 4)
local tab = vim.api.nvim_get_current_tabpage()
assert(await_rename('wrong base', tab, 'active') == false, 'must not rename base workspace from linked cwd')
assert(#rename_calls == 0, 'base workspace must not be renamed')

vim.env.HERDR_WORKSPACE_ID = 'linked'
snapshot(workspaces, 'base')
assert(await_rename('wrong pane', tab, 'active') == false, 'pane must belong to target workspace')
assert(#rename_calls == 0, 'workspace id must match Herdr pane association')

vim.env.HERDR_WORKSPACE_ID = 'linked'
vim.cmd('cd ' .. vim.fn.fnameescape(base_root))
snapshot(workspaces, 'linked')
assert(await_rename('wrong cwd', tab, 'active') == false, 'must reject cwd/worktree mismatch')
assert(#rename_calls == 0, 'mismatched cwd must not rename')

vim.cmd('cd ' .. vim.fn.fnameescape(linked))
snapshot({ workspaces[2] }, 'linked')
assert(await_rename('no base', tab, 'active') == false, 'must require a base workspace for the same repo')
assert(#rename_calls == 0, 'missing base workspace must not rename')

snapshot(workspaces, 'linked')
assert(await_rename('valid title', tab, 'active') == true, 'valid linked workspace should rename')
assert(rename_calls[1].workspace_id == 'linked' and rename_calls[1].title == 'valid title')
assert(await_rename('stale tab', tab + 1, 'active') == false, 'stale tab should be ignored')
assert(await_rename('stale session', tab, 'old') == false, 'stale session should be ignored')
assert(#rename_calls == 1, 'stale sessions/tabs must not rename')
current_snapshot.panes = 'malformed'
assert(await_rename('malformed panes', tab, 'active') == false, 'malformed panes must fail closed')
snapshot(workspaces, 'linked')
current_snapshot.workspaces = 'malformed'
assert(await_rename('malformed workspaces', tab, 'active') == false, 'malformed workspaces must fail closed')
snapshot(workspaces, 'linked')

local function reject_during_pending(mutate, restore, delay)
  local before = #rename_calls
  git_callback_delay = delay or 0
  vim.defer_fn(mutate, 2)
  assert(await_rename('stale pending', tab, 'active') == false, 'stale state during awaits must reject rename')
  restore()
  git_callback_delay = 0
  assert(#rename_calls == before, 'stale pending state must not dispatch rename')
end
snapshot(workspaces, 'linked')
reject_during_pending(function() registry.sessions[tab].session_id = 'replacement' end, function() registry.sessions[tab].session_id = 'active' end, 20)
reject_during_pending(function() vim.cmd('cd ' .. vim.fn.fnameescape(base_root)) end, function() vim.cmd('cd ' .. vim.fn.fnameescape(linked)) end, 20)
reject_during_pending(function() vim.env.HERDR_WORKSPACE_ID = 'base' end, function() vim.env.HERDR_WORKSPACE_ID = 'linked' end, 20)
reject_during_pending(function() vim.env.HERDR_ENV = '0' end, function() vim.env.HERDR_ENV = '1' end, 20)
reject_during_pending(function() vim.env.HERDR_PANE_ID = 'other-pane' end, function() vim.env.HERDR_PANE_ID = 'w3:p1' end, 20)
local extra_tab
reject_during_pending(function() vim.cmd('tabnew'); extra_tab = vim.api.nvim_get_current_tabpage() end, function()
  if extra_tab and vim.api.nvim_tabpage_is_valid(extra_tab) then
    vim.api.nvim_set_current_tabpage(extra_tab)
    vim.cmd('tabclose!')
  end
  vim.api.nvim_set_current_tabpage(tab)
end, 20)
reject_during_pending(function() current_snapshot.panes[1].workspace_id = 'base' end, function() current_snapshot.panes[1].workspace_id = 'linked' end, 20)
reject_during_pending(function() current_snapshot.workspaces[2].worktree.checkout_path = base_root end, function() current_snapshot.workspaces[2].worktree.checkout_path = linked end, 20)

local Shell = require('utils.shell')
local heartbeat = 0
local timer = vim.uv.new_timer()
timer:start(5, 5, function() heartbeat = heartbeat + 1 end)
local delay_ok = Shell.async_cmd('sh', { '-c', 'sleep 0.12' }, nil)
timer:stop(); timer:close()
assert(delay_ok and heartbeat >= 3, 'event loop heartbeat must run during delayed process')

vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
vim.system = original_system
vim.env.HERDR_ENV = original_herdr_env
vim.env.HERDR_WORKSPACE_ID = original_workspace_id
vim.env.HERDR_PANE_ID = original_pane_id
vim.env.HERDR_BIN_PATH = original_bin_path
package.loaded['agentic.session_registry'] = nil
vim.fn.delete(root, 'rf')
print('workspace context regressions passed')
end, function() completed = true end)
assert(vim.wait(120000, function() return completed end, 10), 'async workspace tests timed out')
