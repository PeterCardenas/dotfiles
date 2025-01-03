local async = require('utils.async')

---@async
---@param prev_cmd_output string[]
---@return boolean whether account was switched
local function maybe_switch_account(prev_cmd_output)
  -- TODO: Handle the case where there are more than 2 accounts
  if #prev_cmd_output == 1 and prev_cmd_output[1]:match('GraphQL: Could not resolve to a Repository') then
    local success, output = require('utils.shell').async_cmd('gh', {
      'auth',
      'switch',
    })
    vim.schedule(function()
      if not success then
        vim.notify('Could not switch account:\n' .. table.concat(output, '\n'), vim.log.levels.ERROR)
      else
        -- Success message should be in the output.
        vim.notify(output[1], vim.log.levels.INFO)
      end
    end)
    return success
  end
  return false
end

---@async
---@param retry? boolean
---@return boolean, string
local function get_repo_url(retry)
  local shell = require('utils.shell')
  local success, output = shell.async_cmd('gh', { 'repo', 'view', '--json=url', '-q=.url' })
  if not success and not retry then
    local switched = maybe_switch_account(output)
    if switched then
      return get_repo_url(true)
    end
  end
  if not success then
    return false, table.concat(output, '\n')
  end
  local repo_url = output[1]
  return success, repo_url
end

---@async
---@param commit_sha string
---@param is_retry? boolean
---@return string | nil
local function get_pr_url(commit_sha, is_retry)
  local shell = require('utils.shell')
  local success, output = shell.async_cmd('gh', {
    'pr',
    'list',
    '--state',
    'merged',
    '--json',
    'url,mergeCommit',
    '--search',
    commit_sha,
    '--jq',
    '.[]| select(.mergeCommit.oid == "' .. commit_sha .. '") | .url',
  })
  -- Handle case when auth
  if not is_retry and not success then
    local switched = maybe_switch_account(output)
    if not switched then
      return nil
    end
    return get_pr_url(commit_sha, true)
  end
  if not success or #output == 0 then
    return nil
  end
  return output[1]
end

---@async
---@param commit_sha string
---@return string
local function get_commit_url(commit_sha)
  local success, output = get_repo_url()
  if not success then
    return ''
  end
  local repo_url = output
  local commit_url = repo_url .. '/commit/' .. commit_sha
  return commit_url
end

vim.api.nvim_create_user_command('GHPR', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_entry = require('gitsigns.cache').cache[bufnr]
  if not cache_entry then
    vim.notify('No blame for current buffer', vim.log.levels.ERROR)
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local config = require('gitsigns.config').config
  local gitsigns_async = require('gitsigns.async')
  -- gitsigns async and plenary async are not compatible with each other
  -- So use gitsigns async just for getting blame info.
  ---@type fun(cb: fun(blame_info: Gitsigns.BlameInfo?): nil): nil
  local run = gitsigns_async.create(
    0,
    ---@async
    ---@return Gitsigns.BlameInfo?
    function()
      local blame_info = cache_entry:get_blame(lnum, config.current_line_blame_opts)
      return blame_info
    end
  )
  run(function(blame_info)
    async.void(
      ---@async
      function()
        if not blame_info then
          vim.schedule(function()
            vim.notify('Blame has not been loaded yet.', vim.log.levels.ERROR)
          end)
          return
        end
        local not_committed_sha = require('gitsigns.git.blame').get_blame_nc('', lnum).commit.sha
        if blame_info.commit.sha == not_committed_sha then
          vim.schedule(function()
            vim.notify('Current line not committed yet.', vim.log.levels.ERROR)
          end)
          return
        end
        local commit_sha = blame_info.commit.sha
        local pr_url = get_pr_url(commit_sha)
        if not pr_url then
          local commit_url = get_commit_url(commit_sha)
          vim.notify('No PR created yet.\nCopied commit link to clipboard:\n' .. commit_url, vim.log.levels.WARN)
          vim.schedule(function()
            vim.fn.setreg('+', commit_url)
          end)
          return
        end
        vim.notify('Copied PR link to clipboard:\n' .. pr_url, vim.log.levels.INFO)
        vim.schedule(function()
          vim.fn.setreg('+', pr_url)
        end)
      end
    )
  end)
end, { nargs = 0, desc = 'Open/Copy GitHub PR link for current line' })

local function relative_path_to_git_root()
  local current_file_paths = vim.fn.expand('%:p')
  local current_file = current_file_paths[1]
  if type(current_file_paths) == 'string' then
    current_file = current_file_paths
  end
  local git_root = require('utils.file').get_git_root()

  if git_root and vim.fn.isdirectory(git_root) == 1 then
    if vim.fn.stridx(current_file, git_root) == 0 then
      return vim.fn.substitute(current_file, '^' .. git_root .. '/', '', '')
    end
  end

  return nil
end

---@async
---@return boolean, string
local function common_ancestor_commit_with_master()
  local default_branch_success, default_branch_output = require('utils.git').get_default_branch()
  if not default_branch_success then
    return false, 'failed to get default branch:\n' .. default_branch_output
  end
  local default_branch = default_branch_output
  local shell = require('utils.shell')
  local success, output = shell.async_cmd('git', { 'merge-base', 'HEAD', 'origin/' .. default_branch })
  if not success then
    return false, table.concat(output, '\n')
  end
  local commit_sha = output[1]
  return success, commit_sha
end

vim.api.nvim_create_user_command('GHFile', function()
  local start_lnum, end_lnum = vim.fn.line("'<"), vim.fn.line("'>")
  local filepath = relative_path_to_git_root()
  if not filepath then
    vim.notify('Could not find relative path to git root', vim.log.levels.ERROR)
    return
  end
  local current_line_nr = vim.fn.line('.')
  async.void(
    ---@async
    function()
      local success, output = get_repo_url()
      if not success then
        vim.notify('Could not get repo url:\n' .. output, vim.log.levels.ERROR)
        return
      end
      local repo_url = output
      success, output = common_ancestor_commit_with_master()
      if not success then
        vim.notify('Could not get common ancestor commit with default branch:\n' .. output, vim.log.levels.ERROR)
        return
      end
      local commit_sha = output
      local file_url = repo_url .. '/blob/' .. commit_sha .. '/' .. filepath
      if start_lnum ~= 0 then
        file_url = file_url .. '#L' .. start_lnum
        if end_lnum ~= start_lnum then
          file_url = file_url .. '-L' .. end_lnum
        end
      else -- If no visual selection, then just copy the link to the current line
        file_url = file_url .. '#L' .. current_line_nr
      end
      vim.notify('Copied file link to clipboard:\n' .. file_url, vim.log.levels.INFO)
      vim.schedule(function()
        vim.fn.setreg('+', file_url)
      end)
    end
  )
end, { nargs = 0, desc = 'Open/Copy GitHub file link on master for current file', range = true })

vim.api.nvim_create_user_command('CreatePR', function()
  require('octo.commands').create_pr()
end, { nargs = 0, desc = 'Create a PR for the current branch' })

vim.api.nvim_create_user_command('EditPR', function()
  async.void(
    ---@async
    function()
      local success, output = require('utils.shell').async_cmd('gh', { 'pr', 'view', '--json=number', '--jq=.number' })
      if not success then
        vim.schedule(function()
          vim.notify('Could not find PR for current branch\n' .. table.concat(output, '\n'), vim.log.levels.ERROR)
        end)
        return
      end
      local pr_number = output[1]
      vim.schedule(function()
        require('octo.utils').get_pull_request(pr_number)
      end)
    end
  )
end, { nargs = 0, desc = 'Edit the PR for the current branch' })

local nmap = require('utils.keymap').nmap

nmap('Show blame for current line', 'gh', function()
  local config = require('gitsigns.config').config
  require('gitsigns.actions').blame_line(config.current_line_blame_opts)
end)
vim.keymap.set({ 'n', 'v' }, '<leader>gp', function()
  require('gitsigns.actions').preview_hunk()
end, { desc = 'Preview git hunk' })
vim.keymap.set({ 'n', 'v' }, '<leader>gr', function()
  require('gitsigns.actions').reset_hunk()
end, { desc = 'Reset git hunk' })
vim.keymap.set({ 'n', 'v' }, '<leader>gs', function()
  require('gitsigns.actions').stage_hunk()
end, { desc = 'Stage git hunk' })
vim.keymap.set({ 'n', 'v' }, '<leader>gu', function()
  require('gitsigns.actions').undo_stage_hunk()
end, { desc = 'Undo last staged git hunk in current buffer' })
vim.keymap.set({ 'n', 'v' }, '<leader>gj', function()
  require('gitsigns.actions').nav_hunk('next')
end, { desc = 'Jump to next hunk' })
vim.keymap.set({ 'n', 'v' }, '<leader>gk', function()
  require('gitsigns.actions').nav_hunk('prev')
end, { desc = 'Jump to previous hunk' })

---@type LazyPluginSpec[]
return {
  {
    -- Adds GitHub integration
    'pwntester/octo.nvim',
    cmd = { 'Octo' },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'ibhagwan/fzf-lua',
      'echasnovski/mini.icons',
    },
    config = function()
      require('octo').setup({
        ssh_aliases = {
          ['personal-github.com'] = 'github.com',
          ['work-github.com'] = 'github.com',
        },
        github_hostname = 'github.com',
        remotes = { 'origin', 'upstream' },
        picker = 'fzf-lua',
        default_merge_method = 'rebase',
        suppress_missing_scope = {
          projects_v2 = true,
        },
      })
    end,
  },
  {
    -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      -- See `:help gitsigns.txt`
      require('gitsigns').setup({
        signs = {
          add = { text = '+' },
          change = { text = '~' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
        },
        -- Currently causing performance issues with gopls, so disabled for now.
        -- Hint: Maybe inlay hints are causing this issue.
        current_line_blame = false,
        current_line_blame_opts = {
          extra_opts = { '-C' },
        },
        on_attach = function(bufnr) end,
      })
    end,
  },
}
