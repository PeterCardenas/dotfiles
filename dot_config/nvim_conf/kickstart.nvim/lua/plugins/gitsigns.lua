local Async = require('utils.async')
local File = require('utils.file')
local Shell = require('utils.shell')
local Git = require('utils.git')
local Buf = require('utils.buf')
local Config = require('utils.config')

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
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  if buf_name == '' then
    buf_name = vim.b[bufnr].bufpath
  end
  if buf_name == '' then
    vim.notify('Could not get buffer name', vim.log.levels.ERROR)
    return
  end
  local buf_dir = vim.fn.fnamemodify(buf_name, ':p:h')
  local cache_entry = require('gitsigns.cache').cache[bufnr]
  if not cache_entry then
    vim.notify('No blame for current buffer', vim.log.levels.ERROR)
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local config = require('gitsigns.config').config
  local gitsigns_async = require('gitsigns.async')
  ---@diagnostic disable-next-line: param-type-mismatch
  local get_blame_task = gitsigns_async.run(cache_entry.get_blame, cache_entry, lnum, config.current_line_blame_opts)
  get_blame_task:await(function(err, blame_info) ---@param blame_info Gitsigns.BlameInfo?
    if err then
      vim.notify('Getting blame info failed:\n' .. tostring(err), vim.log.levels.ERROR)
      return
    end
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

---@param filename string
local function relative_path_to_git_root(filename)
  local current_file = vim.fn.fnamemodify(filename, ':p')
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
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name == '' then
    buf_name = vim.b[0].bufpath
  end
  local buf_dir = vim.fn.fnamemodify(buf_name, ':p:h')
  local filepath = relative_path_to_git_root(buf_name)
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

---@type table<integer,boolean>
local blame_fetch_map = {}

vim.api.nvim_create_autocmd({ 'BufEnter', 'CursorMoved', 'WinScrolled' }, {
  group = vim.api.nvim_create_augroup('gitsigns-prefetch-blame', { clear = true }),
  callback = function(opts)
    local bufnr = opts.buf
    local cache_entry = require('gitsigns.cache').cache[bufnr]
    if not cache_entry then
      return
    end
    local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
    if blame_fetch_map[bufnr] then
      return
    end
    blame_fetch_map[bufnr] = true
    local config = require('gitsigns.config').config
    local gitsigns_async = require('gitsigns.async')
    local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
    local start_lnum = math.max(1, vim.fn.line('w0') - 10, cursor_lnum - 20)
    local end_lnum = math.min(buf_line_count, vim.fn.line('w$') + 10, cursor_lnum + 20)
    ---@diagnostic disable-next-line: param-type-mismatch
    local prefetch_blame_task = gitsigns_async.run(cache_entry.get_blame, cache_entry, { start_lnum, end_lnum }, config.current_line_blame_opts)
    prefetch_blame_task:await(function(err)
      if err then
        return
      end
      blame_fetch_map[bufnr] = false
    end)
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
  group = vim.api.nvim_create_augroup('octo.remove-close-buffer-mapping', {}),
  callback = function(args)
    local bufnr = args.buf
    vim.keymap.set('n', '<leader>cc', Buf.close_current_buffer, { buffer = bufnr, desc = 'Close buffer' })
  end,
})

vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  pattern = 'octo://*',
  group = vim.api.nvim_create_augroup('octo.reviews.thread-panel', {}),
  callback = function(opts)
    local bufnr = opts.buf
    vim.keymap.set('n', '<leader>rt', function()
      require('octo.reviews.thread-panel').show_review_threads(true)
    end, { buffer = bufnr, desc = 'Review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rs', function()
      require('octo.reviews').add_review_comment(true)
    end, { buffer = bufnr, desc = 'Add suggestion to review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rf', function()
      require('octo.commands').reaction_action('confused')
    end, { buffer = bufnr, desc = 'React with confused to review thread' })
    vim.keymap.set({ 'n', 'v' }, '<leader>rd', function()
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
  require('octo.pickers.fzf-lua.pickers.search')({ prompt = 'is:pr sort:updated-desc user-review-requested:@me is:open' })
end, { nargs = 0, desc = 'List all PRs that can be reviewed' })
vim.api.nvim_create_user_command('ReviewedPRs', function()
  require('octo.pickers.fzf-lua.pickers.search')({ prompt = 'is:pr sort:updated-desc reviewed-by:@me is:open' })
end, { nargs = 0, desc = 'List all PRs I have reviewed' })

vim.api.nvim_create_user_command('MyPRs', function(args)
  local all = args.args == 'all'
  local status_filter = all and '' or 'is:open'
  require('octo.pickers.fzf-lua.pickers.search')({ prompt = 'is:pr sort:updated-desc author:@me ' .. status_filter })
end, {
  nargs = '?',
  desc = 'List all PRs that I have created',
  complete = function()
    return { 'all' }
  end,
})

vim.api.nvim_create_user_command('GHNotifs', function(args)
  local all = args.args == 'all'
  require('octo.pickers.telescope.provider').notifications({ all = all })
end, {
  nargs = '?',
  desc = 'GitHub notifications',
  complete = function()
    return { 'all' }
  end,
})

local lazy_load_octo = vim.api.nvim_create_augroup('lazy_load_octo', { clear = true })
vim.api.nvim_create_autocmd({ 'BufReadCmd' }, {
  group = lazy_load_octo,
  pattern = 'octo://*',
  callback = function(args)
    require('octo').load_buffer({ bufnr = args.buf })
  end,
})
vim.api.nvim_create_autocmd({ 'BufReadPre' }, {
  group = lazy_load_octo,
  pattern = '*/octo.nvim/lua/octo/gh/*.lua',
  callback = function()
    require('octo')
  end,
})

---@type LazyPluginSpec[]
return {
  {
    -- Adds GitHub integration
    'PeterCardenas/octo.nvim',
    branch = 'dev',
    cmd = { 'Octo' },
    dependencies = {
      'nvim-lua/plenary.nvim',
      Config.FZF_LUA_REPO,
      'echasnovski/mini.icons',
      -- Not actual dependencies, but plugins that I want to be lazy loaded in addition to octo.nvim
      'Bekaboo/dropbar.nvim',
      'nvim-treesitter/nvim-treesitter-context',
    },
    config = function()
      vim.api.nvim_del_augroup_by_id(lazy_load_octo)
      -- TODO: Saving PR description doesn't trigger workflow. Should use gh pr edit command to do so.
      -- TODO: Add option for keeping diff shown when viewing a comment thread.
      -- TODO: Make virtual text for comments brighter when hovering on the lines associated with the comment.
      -- TODO: Add user events to use for auto commands to trigger for fidget.nvim notifications.
      -- TODO: Add add to project event in issue
      -- TODO: Load resolved comments previous reviews in current review.
      -- TODO: Search across files in a PR.
      -- TODO: add ignore whitespace options: set diffopt+=iwhiteall
      -- TODO: Octo review close closes all pr review tabs
      -- TODO: group review files by shared directories
      -- TODO: Add some indicator of the range referenced by a comment
      -- TODO: keymap to go to next/previous diffhunk
      -- TODO: toggle as file viewed when not in file panel should toggle the current file not the last one the cursor was on in the file panel
      -- TODO: refresh PR buffer when review submitted
      -- TODO: pr checkout "Switched to a new branch x" should be info notification not error
      -- TODO: issue status from notification preview does not match issue buffer
      -- TODO: status column for dirty state doesn't update until move cursor
      -- TODO: improve error message when adding pull request comment when already in pr review
      -- TODO: add codeownership in file panel
      -- TODO: add <leader>gi to open referenced issue in timeline
      -- TODO: handle orgs/owner/name/discussions in hover preview
      -- TODO: highlight pr number based on open/closed in Octo pr search
      -- TODO: highlight/visualize suggestions better
      -- TODO: add extmarks for diff filetype based on filetype of hunks
      -- TODO: highlight injected languages in diffhunk
      -- TODO: fetch and show diff for git lfs
      -- TODO: open discussions with goto_issue
      -- TODO: hide tooltip after moving cursor
      -- TODO: show (outdated) on pr comment
      -- TODO: show entire contents in fzf-lua preview
      -- TODO: escape double quotes inside review comments.
      -- TODO: improve performance on large files
      -- TODO: fix diff highlighting
      -- TODO: add auto merge command
      -- TODO: update title status when `Octo pr ready` and `Octo pr merge` are called
      -- TODO: add profile images with /users/<login> .avatar_url
      -- TODO: add UNSTABLE reason: e.g. baseRef.branchProtectionRule.requiresConversationResolution
      --       Reference: https://docs.github.com/en/graphql/reference/objects#branchprotectionrule
      --       Reference: https://docs.github.com/en/graphql/reference/enums#mergestatestatus
      if not vim.env.GH_TOKEN then
        vim.wait(1000, function()
          return _G.GH_TOKEN ~= nil
        end, 100)
        if not _G.GH_TOKEN then
          vim.notify('User not set up for gh cli', vim.log.levels.ERROR)
        else
          vim.env.GH_TOKEN = _G.GH_TOKEN
        end
      end
      require('octo.utils').state_icon_map.COMMENTED = ' '
      require('octo').setup({
        timeout = math.huge,
        debug = {
          notify_missing_timeline_items = true,
        },
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
        default_merge_method = 'squash',
        snippet_context_lines = 6,
        suppress_missing_scope = {
          projects_v2 = true,
        },
        reviews = {
          auto_show_threads = false,
        },
        mappings = {
          discussion = {
            -- Remove conflict with <C-y> for scrolling
            copy_url = { lhs = '<leader>di', desc = 'copy url to system clipboard' },
          },
          pull_request = {
            -- Remove conflict with <C-y> for scrolling
            copy_url = { lhs = '<leader>pu', desc = 'copy url to system clipboard' },
            copy_sha = { lhs = '<leader>ph', desc = 'copy sha to system clipboard' },
          },
          issue = {
            -- Remove conflict with <C-y> for scrolling
            copy_url = { lhs = '<leader>iu', desc = 'copy url to system clipboard' },
            add_assignee = { lhs = '<leader>ia', desc = 'add assignee' },
          },
          review_thread = {
            add_suggestion = { lhs = '<leader>cs', desc = 'add suggestion' },
          },
          review_diff = {
            add_review_suggestion = { lhs = '<leader>cs', desc = 'add suggestion' },
            copy_sha = { lhs = '<leader>ph', desc = 'copy sha to system clipboard' },
          },
          submit_win = {
            approve_review = { lhs = '<C-s>', desc = 'approve review', mode = { 'n', 'i' } },
          },
          notification = {
            read = { lhs = '<C-r>', desc = 'read notification' },
            unsubscribe = { lhs = '<C-x>', desc = 'unsubscribe from notifications' },
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
        max_file_length = 60000,
        gh = true,
        diff_opts = {
          internal = true,
          indent_heuristic = true,
          linematch = 40,
          ignore_blank_lines = false,
          ignore_whitespace_change = false,
          ignore_whitespace_change_at_eol = false,
          ignore_whitespace = false,
        },
        signs = {
          add = { text = '+' },
          change = { text = '~' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
        },
        attach_to_untracked = true,
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
