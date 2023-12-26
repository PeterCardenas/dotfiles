vim.api.nvim_create_user_command('PRLink', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_entry = require('gitsigns.cache').cache[bufnr]
  if not cache_entry then
    vim.notify("No blame for current buffer", vim.log.levels.ERROR)
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local config = require('gitsigns.config').config
  local blame_info = cache_entry:get_blame(lnum, config.current_line_blame_opts)
  if not blame_info then
    vim.notify("No blame for current line", vim.log.levels.ERROR)
    return
  end
  local commit_message = blame_info.commit.summary
  local pr_number = commit_message:match('%(#(%d+)%)$')
  if not pr_number then
    vim.notify("No PR number in commit message", vim.log.levels.ERROR)
    return
  end
  local repo_url = vim.fn.systemlist('gh repo view --json=url -q ".url"')[1]
  local pr_url = repo_url .. '/pull/' .. pr_number
  local could_open = require('utils').system_open(pr_url, true)
  if could_open then
    vim.notify("Opened PR in browser", vim.log.levels.INFO)
  else
    vim.notify("Copied PR link to clipboard", vim.log.levels.INFO)
    vim.fn.setreg('+', pr_url)
  end
end, { nargs = 0, desc = "Copy GitHub PR link for current line to clipboard" })

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
      },
      on_attach = function(bufnr)
        vim.keymap.set({ 'n', 'v' }, '<leader>gp', require('gitsigns.actions').preview_hunk,
          { buffer = bufnr, desc = 'Preview git hunk' })

        vim.keymap.set({ 'n', 'v' }, '<leader>gr', require('gitsigns.actions').reset_hunk,
          { buffer = bufnr, desc = 'Reset git hunk' })

        vim.keymap.set({ 'n', 'v' }, '<leader>gs', require('gitsigns.actions').stage_hunk,
          { buffer = bufnr, desc = 'Stage git hunk' })
        vim.keymap.set({ 'n', 'v' }, '<leader>gu', require('gitsigns.actions').undo_stage_hunk,
          { buffer = bufnr, desc = 'Undo last staged git hunk in current buffer' })

        -- don't override the built-in and fugitive keymaps
        local gs = package.loaded.gitsigns
        vim.keymap.set({ 'n', 'v' }, '<leader>gj', function()
          if vim.wo.diff then return '<leader>gj' end
          vim.schedule(function() gs.next_hunk() end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = "Jump to next hunk" })
        vim.keymap.set({ 'n', 'v' }, '<leader>gk', function()
          if vim.wo.diff then return '<leader>gk' end
          vim.schedule(function() gs.prev_hunk() end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = "Jump to previous hunk" })
      end,
    })
  end,
}
