local Async = require('utils.async')
local File = require('utils.file')
local Shell = require('utils.shell')
local Git = require('utils.git')

---@async
---@param cwd string
---@return boolean, string
local function get_repo_url(cwd)
  local success, output = Shell.async_cmd('gh', { 'repo', 'view', '--json=url', '-q=.url' }, cwd)
  if not success then
    return false, table.concat(output, '\n')
  end
  local repo_url = output[1]
  return success, repo_url
end

---@async
---@param commit_sha string
---@param cwd string
---@return string | nil
local function get_pr_url(commit_sha, cwd)
  local shell = Shell
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
  }, cwd)
  if not success or #output == 0 then
    return nil
  end
  return output[1]
end

---@async
---@param commit_sha string
---@param cwd string
---@return string
local function get_commit_url(commit_sha, cwd)
  local success, output = get_repo_url(cwd)
  if not success then
    return ''
  end
  local repo_url = output
  local commit_url = repo_url .. '/commit/' .. commit_sha
  return commit_url
end

vim.api.nvim_create_user_command('GHPR', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_dir = vim.fn.expand('%:p:h')
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
  ---@type fun(cb: fun(err, blame_info: Gitsigns.BlameInfo?): nil): nil
  local run = gitsigns_async.create(
    0,
    ---@async
    ---@return Gitsigns.BlameInfo?
    function()
      local blame_info = cache_entry:get_blame(lnum, config.current_line_blame_opts)
      return blame_info
    end
  )
  run(function(err, result)
    if err then
      vim.notify('Getting blame info failed:\n' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    local blame_info = result
    if not blame_info then
      vim.notify('Blame has not been loaded yet.', vim.log.levels.ERROR)
      return
    end
    local commit_sha = blame_info.commit.sha
    Async.void(
      ---@async
      function()
        local not_committed_sha = require('gitsigns.git.blame').get_blame_nc('', lnum).commit.sha
        if commit_sha == not_committed_sha then
          vim.schedule(function()
            vim.notify('Current line not committed yet.', vim.log.levels.ERROR)
          end)
          return
        end
        local pr_url = get_pr_url(commit_sha, buf_dir)
        if not pr_url then
          local commit_url = get_commit_url(commit_sha, buf_dir)
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
  local current_file = vim.fn.expand('%:p')
  local git_root = File.get_git_root(current_file)

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
  local default_branch_success, default_branch_output = Git.get_default_branch()
  if not default_branch_success then
    return false, 'failed to get default branch:\n' .. default_branch_output
  end
  local default_branch = default_branch_output
  local shell = Shell
  local success, output = shell.async_cmd('git', { 'merge-base', 'HEAD', 'origin/' .. default_branch })
  if not success then
    return false, table.concat(output, '\n')
  end
  local commit_sha = output[1]
  return success, commit_sha
end

vim.api.nvim_create_user_command('GHFile', function()
  local start_lnum, end_lnum = vim.fn.line("'<"), vim.fn.line("'>")
  local buf_dir = vim.fn.expand('%:p:h')
  local filepath = relative_path_to_git_root()
  if not filepath then
    vim.notify('Could not find relative path to git root', vim.log.levels.ERROR)
    return
  end
  local current_line_nr = vim.fn.line('.')
  Async.void(
    ---@async
    function()
      local success, output = get_repo_url(buf_dir)
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
  Async.void(
    ---@async
    function()
      local success, output = Shell.async_cmd('gh', { 'pr', 'view', '--json=number', '--jq=.number' })
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

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  group = vim.api.nvim_create_augroup('gitsigns-prefetch-blame', { clear = true }),
  callback = function(opts)
    ---@type integer
    local bufnr = opts.buf
    local cache_entry = require('gitsigns.cache').cache[bufnr]
    if not cache_entry then
      return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local config = require('gitsigns.config').config
    local gitsigns_async = require('gitsigns.async')
    -- gitsigns async and plenary async are not compatible with each other
    -- So use gitsigns async just for getting blame info.
    ---@type fun(cb?: fun(blame_info: Gitsigns.BlameInfo?): nil): nil
    local run = gitsigns_async.create(
      0,
      ---@async
      ---@return Gitsigns.BlameInfo?
      function()
        local blame_info = cache_entry:get_blame(lnum, config.current_line_blame_opts)
        return blame_info
      end
    )
    run()
  end,
})

-- TODO: show github pr preview, similar to https://github.com/dlvhdr/gh-blame.nvim/blob/main/lua/gh-blame/gh.lua, but with better loading state.
nmap('Show blame for current line', 'gh', function()
  local config = require('gitsigns.config').config
  require('gitsigns.actions').blame_line(config.current_line_blame_opts)
end)
nmap('Show blame for current line with -C', 'gH', function()
  local current_line_blame_opts = vim.deepcopy(require('gitsigns.config').config.current_line_blame_opts)
  local extra_opts = current_line_blame_opts.extra_opts or {}
  extra_opts[#extra_opts + 1] = '-C'
  current_line_blame_opts.extra_opts = extra_opts
  require('gitsigns.actions').blame_line(current_line_blame_opts)
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
  require('gitsigns.actions').stage_hunk()
end, { desc = 'Undo last staged git hunk in current buffer' })
vim.keymap.set({ 'n', 'v' }, '<leader>gj', function()
  require('gitsigns.actions').nav_hunk('next')
end, { desc = 'Jump to next hunk' })
vim.keymap.set({ 'n', 'v' }, '<leader>gk', function()
  require('gitsigns.actions').nav_hunk('prev')
end, { desc = 'Jump to previous hunk' })

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  pattern = 'octo://*',
  group = vim.api.nvim_create_augroup('octo.reviews.thread-panel', {}),
  callback = function(opts)
    ---@type integer
    local bufnr = opts.buf
    vim.keymap.set('n', '<leader>rt', function()
      require('octo.reviews.thread-panel').show_review_threads(true)
    end, { buffer = bufnr, desc = 'Review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rca', function()
      local current_review = require('octo.reviews').get_current_review()
      -- HACK: Go into insert mode since starting in visual mode causes the cursor to be stuck in visual mode
      vim.cmd('startinsert')
      if current_review and require('octo.utils').in_diff_window() then
        current_review:add_comment(false)
      else
        require('octo.commands').add_comment()
      end
    end, { buffer = bufnr, desc = 'Add comment to review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rs', function()
      require('octo.reviews').add_review_comment(true)
    end, { buffer = bufnr, desc = 'Add suggestion to review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rf', function()
      require('octo.commands').reaction_action('confused')
    end, { buffer = bufnr, desc = 'React with confused to review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rcd', function()
      require('octo.commands').delete_comment()
    end, { buffer = bufnr, desc = 'Delete review comment' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rrt', function()
      require('octo.commands').resolve_thread()
    end, { buffer = bufnr, desc = 'Resolve thread' })
    -- Re-add leap keymaps
    vim.keymap.set({ 'n', 'v', 'x', 'o' }, 's', '<Plug>(leap-forward)', { buffer = bufnr })
    vim.keymap.set({ 'n', 'v', 'x', 'o' }, 'S', '<Plug>(leap-backward)', { buffer = bufnr })
    vim.keymap.set({ 'n', 'v', 'x', 'o' }, 'gs', '<Plug>(leap-from-window)', { buffer = bufnr })
  end,
})

-- HACK: This user command is added since the keymap `<C-a>` does not work.
vim.api.nvim_create_user_command('ApprovePR', function()
  require('octo.mappings').approve_review()
end, { nargs = 0, desc = 'Approve a PR' })

vim.api.nvim_create_user_command('ReviewablePRs', function()
  require('octo.pickers.telescope.provider').search({ prompt = 'is:pr sort:updated-desc user-review-requested:@me is:open' })
end, { nargs = 0, desc = 'List all PRs that can be reviewed' })

vim.api.nvim_create_user_command('MyPRs', function()
  require('octo.pickers.telescope.provider').search({ prompt = 'is:pr sort:updated-desc author:@me is:open' })
end, { nargs = 0, desc = 'List all PRs that I have created' })

vim.api.nvim_create_user_command('GHNotifs', function()
  require('octo.pickers.telescope.provider').notifications()
end, { nargs = 0, desc = 'GitHub notifications' })

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
      -- Not actual dependencies, but plugins that I want to be lazy loaded in addition to octo.nvim
      'Bekaboo/dropbar.nvim',
      'nvim-treesitter/nvim-treesitter-context',
    },
    config = function()
      -- TODO: Octo PR buffer doesn't have correct highlighting when first loaded. Need to call some other Octo command to trigger it, e.g. Octo review start.
      -- TODO: Saving PR description doesn't trigger workflow. Should use gh pr edit command to do so.
      -- TODO: Show in virtual text whether a comment is resolved.
      -- TODO: Add option for keeping diff shown when viewing a comment thread.
      -- TODO: Make virtual text for comments brighter when hovering on the lines associated with the comment.
      -- TODO: Add user events to use for auto commands to trigger for fidget.nvim notifications.
      -- TODO: Next thread keymap gets removed sometimes (when switching between tabs maybe?)
      -- TODO: Add add to project event in issue
      -- TODO: Fetch whether a file has been viewed when resuming/starting a review.
      -- TODO: Load resolved comments previous reviews in current review.
      -- TODO: Search across files in a PR.
      if not vim.env.GH_TOKEN then
        vim.notify('User not set up for gh cli', vim.log.levels.ERROR)
      end
      require('octo').setup({
        ssh_aliases = {
          ['personal-github.com'] = 'github.com',
          ['work-github.com'] = 'github.com',
        },
        gh_env = {
          GH_TOKEN = vim.env.GH_TOKEN,
        },
        github_hostname = 'github.com',
        remotes = { 'origin', 'upstream' },
        picker = 'fzf-lua',
        default_merge_method = 'rebase',
        suppress_missing_scope = {
          projects_v2 = true,
        },
        reviews = {
          auto_show_threads = false,
        },
        mappings = {
          pull_request = {
            -- Unmap from <C-y> default
            copy_url = { lhs = '<leader>pu', desc = 'copy url to system clipboard' },
          },
          issue = {
            -- Unmap from <C-y> default
            copy_url = { lhs = '<leader>pu', desc = 'copy url to system clipboard' },
          },
          review_thread = {
            add_comment = { lhs = '<leader>rc', desc = 'add comment' },
            add_suggestion = { lhs = '<leader>rs', desc = 'add suggestion' },
            react_confused = { lhs = '<leader>rf', desc = 'react with confused' },
          },
          review_diff = {
            add_comment = { lhs = '<leader>rc', desc = 'add comment' },
            add_suggestion = { lhs = '<leader>rs', desc = 'add suggestion' },
            react_confused = { lhs = '<leader>rf', desc = 'react with confused' },
          },
          notification = {
            read = { lhs = '<C-r>', desc = 'read notification' },
          },
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
        max_file_length = 50000,
        signs = {
          add = { text = '+' },
          change = { text = '~' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
        },
        current_line_blame = false,
        preview_config = {
          border = 'rounded',
          row = 1,
          col = 0,
        },
      })
    end,
  },
}
