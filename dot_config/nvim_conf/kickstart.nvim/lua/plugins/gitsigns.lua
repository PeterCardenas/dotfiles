---@return string
local function get_repo_url()
  local repo_url = vim.fn.systemlist('gh repo view --json=url -q ".url"')[1]
  return repo_url
end

---@param commit_sha string
---@return string | nil
local function get_pr_url(commit_sha)
  local command = "gh pr list --state=merged --json=url,mergeCommit --search='"
    .. commit_sha
    .. "'"
    .. ' --jq=\'.[] | select(.mergeCommit.oid == "'
    .. commit_sha
    .. '") | .url\''
  local result = vim.fn.systemlist(command)[1]
  if result == '' then
    return nil
  end
  return result
end

---@param commit_sha string
---@return string
local function get_commit_url(commit_sha)
  local repo_url = get_repo_url()
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
  local blame_info = cache_entry:get_blame(lnum, config.current_line_blame_opts)
  if not blame_info then
    vim.notify('Blame has not been loaded yet.', vim.log.levels.ERROR)
    return
  end
  if blame_info.commit.author == require('gitsigns.git').not_commited('').author then
    vim.notify('Current line not committed yet.', vim.log.levels.ERROR)
    return
  end
  local commit_sha = blame_info.commit.sha
  local pr_url = get_pr_url(commit_sha)
  if not pr_url then
    local commit_url = get_commit_url(commit_sha)
    vim.fn.setreg('+', commit_url)
    vim.notify('No PR created yet.\nCopied commit link to clipboard:\n' .. commit_url, vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', pr_url)
  vim.notify('Copied PR link to clipboard:\n' .. pr_url, vim.log.levels.INFO)
end, { nargs = 0, desc = 'Open/Copy GitHub PR link for current line' })

local function get_git_root()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel 2> /dev/null')[1]
  return git_root
end

local function relative_path_to_git_root()
  local current_file_paths = vim.fn.expand('%:p')
  local current_file = current_file_paths[1]
  if type(current_file_paths) == 'string' then
    current_file = current_file_paths
  end
  local git_root = get_git_root()

  if git_root and vim.fn.isdirectory(git_root) == 1 then
    if vim.fn.stridx(current_file, git_root) == 0 then
      return vim.fn.substitute(current_file, '^' .. git_root .. '/', '', '')
    end
  end

  return nil
end

local function common_ancestor_commit_with_master()
  local commit_sha = vim.fn.systemlist('git merge-base HEAD origin/master')[1]
  return commit_sha
end

vim.api.nvim_create_user_command('GHFile', function()
  local start_lnum, end_lnum = vim.fn.line("'<"), vim.fn.line("'>")
  if start_lnum == 0 or end_lnum == 0 then
    start_lnum, end_lnum = vim.fn.line('.'), vim.fn.line('.')
  end
  local repo_url = get_repo_url()
  local filepath = relative_path_to_git_root()
  if not filepath then
    vim.notify('Could not find relative path to git root', vim.log.levels.ERROR)
    return
  end
  local commit_sha = common_ancestor_commit_with_master()
  local file_url = repo_url .. '/blob/' .. commit_sha .. '/' .. filepath .. '#L' .. start_lnum .. '-L' .. end_lnum
  vim.notify('Copied file link to clipboard', vim.log.levels.INFO)
  vim.fn.setreg('+', file_url)
end, { nargs = 0, desc = 'Open/Copy GitHub file link on master for current file', range = true })

vim.keymap.set({ 'n' }, '<leader>gh', function()
  require('gitsigns.actions').blame_line()
end, { desc = 'Show blame for current line' })

---@type LazyPluginSpec
return {
  -- Adds git related signs to the gutter, as well as utilities for managing changes
  'lewis6991/gitsigns.nvim',
  priority = 100,
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
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 10,
        virt_text_pos = 'right_align',
      },
      on_attach = function(bufnr)
        vim.keymap.set({ 'n', 'v' }, '<leader>gp', require('gitsigns.actions').preview_hunk, { buffer = bufnr, desc = 'Preview git hunk' })

        vim.keymap.set({ 'n', 'v' }, '<leader>gr', require('gitsigns.actions').reset_hunk, { buffer = bufnr, desc = 'Reset git hunk' })

        vim.keymap.set({ 'n', 'v' }, '<leader>gs', require('gitsigns.actions').stage_hunk, { buffer = bufnr, desc = 'Stage git hunk' })
        vim.keymap.set(
          { 'n', 'v' },
          '<leader>gu',
          require('gitsigns.actions').undo_stage_hunk,
          { buffer = bufnr, desc = 'Undo last staged git hunk in current buffer' }
        )

        -- don't override the built-in and fugitive keymaps
        local gs = package.loaded.gitsigns
        vim.keymap.set({ 'n', 'v' }, '<leader>gj', function()
          if vim.wo.diff then
            return '<leader>gj'
          end
          vim.schedule(function()
            gs.next_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = 'Jump to next hunk' })
        vim.keymap.set({ 'n', 'v' }, '<leader>gk', function()
          if vim.wo.diff then
            return '<leader>gk'
          end
          vim.schedule(function()
            gs.prev_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = 'Jump to previous hunk' })
      end,
    })
  end,
}
