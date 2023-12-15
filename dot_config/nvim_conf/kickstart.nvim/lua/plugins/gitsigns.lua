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
