local M = {}
local limit = 12000

function M.insert(prompt, context)
  return prompt:gsub('<conversation>', function()
    return context .. '<conversation>'
  end, 1)
end

function M.retry(prompt, candidate)
  return prompt .. '\n\nThe previous name was too long. Replace it with a name of 20 characters or fewer:\n' .. candidate
end

local Shell = require('utils.shell')

---@async
local function git(cwd, args)
  local ok, output = Shell.async_cmd('git', args, { cwd = cwd })
  if not ok then return nil end
  return vim.trim(table.concat(output.stdout, '\n'))
end

---@async
local function default_ref(cwd)
  local remotes = git(cwd, { 'remote' })
  if remotes then
    for remote in remotes:gmatch('[^\n]+') do
      local symbolic = git(cwd, { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/' .. remote .. '/HEAD' })
      if symbolic then return symbolic end
    end
  end

  for _, branch in ipairs({ 'main', 'master' }) do
    local remote = git(cwd, { 'config', '--get', 'branch.' .. branch .. '.remote' })
    if remote then
      local ref = remote .. '/' .. branch
      if git(cwd, { 'rev-parse', '--verify', '--quiet', ref }) then return ref end
      if git(cwd, { 'rev-parse', '--verify', '--quiet', branch }) then return branch end
    end
  end
  for _, branch in ipairs({ 'main', 'master' }) do
    if git(cwd, { 'rev-parse', '--verify', '--quiet', branch }) then return branch end
  end
  return nil
end

---@async
function M.is_linked_worktree(cwd)
  local git_dir = git(cwd, { 'rev-parse', '--absolute-git-dir' })
  local common_dir = git(cwd, { 'rev-parse', '--path-format=absolute', '--git-common-dir' })
  return git_dir ~= nil and common_dir ~= nil and vim.fs.normalize(git_dir) ~= vim.fs.normalize(common_dir)
end

local function same_path(first, second)
  if type(first) ~= 'string' or type(second) ~= 'string' then return false end
  local first_realpath = vim.uv.fs_realpath(first)
  local second_realpath = vim.uv.fs_realpath(second)
  return first_realpath ~= nil and first_realpath == second_realpath
end

---@async
function M.matches_linked_worktree(cwd, worktree)
  if type(worktree) ~= 'table' or worktree.is_linked_worktree ~= true or not M.is_linked_worktree(cwd) then return false end
  local checkout_root = git(cwd, { 'rev-parse', '--show-toplevel' })
  local common_dir = git(cwd, { 'rev-parse', '--path-format=absolute', '--git-common-dir' })
  return same_path(checkout_root, worktree.checkout_path) and same_path(common_dir, worktree.repo_key)
end

---Collect workspace Git context; call only from a utils.async coroutine.
---@async
function M.build(cwd)
  local branch = git(cwd, { 'branch', '--show-current' })
  if not branch or branch == '' then return '' end

  local ref = default_ref(cwd)
  local lines = { '<workspace>', 'Branch: ' .. branch }
  if ref then
    lines[#lines + 1] = 'Default branch: ' .. ref
    local base = git(cwd, { 'merge-base', 'HEAD', ref })
    if base then
      local diff = git(cwd, {
        'diff', '--no-ext-diff', '--no-textconv', '--no-color', '--unified=2', base, '--',
        ':!*.env*', ':!*.pem', ':!*.key', ':!*.p12', ':!*.pfx',
        ':!**/secrets/**', ':!**/secret/**', ':!**/*credential*',
        ':!**/.npmrc', ':!**/.netrc', ':!**/id_rsa*', ':!**/id_ed25519*',
      })
      if diff and diff ~= '' then
        if #diff > limit then diff = diff:sub(1, limit) .. '\n[diff truncated]' end
        lines[#lines + 1] = 'Diff against default branch:'
        lines[#lines + 1] = diff
      end
    end
  end
  lines[#lines + 1] = '</workspace>'
  return table.concat(lines, '\n') .. '\n\n'
end

return M
