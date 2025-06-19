vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = vim.api.nvim_create_augroup('TreesitterAttach', { clear = true }),
  callback = function(args)
    local filetype = vim.bo[args.buf].filetype
    -- TODO: Maybe use dockerfile treesitter highlighting when the following is fixed: https://github.com/camdencheek/tree-sitter-dockerfile/issues/51
    if filetype == 'dockerfile' or filetype == 'tmux' or (filetype == 'yaml' and vim.api.nvim_buf_get_name(args.buf):match('template%.yaml$')) then
      return
    end
    pcall(vim.treesitter.start, args.buf)
  end,
})

---@type LazyPluginSpec[]
return {
  -- Sticky scroll
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = 'nvim-treesitter',
    config = function()
      vim.api.nvim_set_hl(0, 'TreesitterContext', { link = 'Normal' })
      vim.api.nvim_set_hl(0, 'TreesitterContextSeparator', { foreground = '#3b4261', background = '#24283b' })
      require('treesitter-context').setup({
        mode = 'topline',
        line_numbers = true,
        max_lines = 10,
        separator = '─',
        multiwindow = true,
        zindex = 41,
      })
    end,
  },
  {
    -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    dependencies = {
      {
        'nvim-treesitter/nvim-treesitter-textobjects',
        branch = 'main',
        config = function()
          require('nvim-treesitter-textobjects').setup({
            select = {
              lookahead = true,
              include_surrounding_whitespace = false,
            },
            move = {
              set_jumps = false,
            },
          })
          ---@param mapping string
          ---@param textobject string
          local function add_select_keymap(mapping, textobject)
            vim.keymap.set({ 'x', 'o' }, mapping, function()
              require('nvim-treesitter-textobjects.select').select_textobject(textobject, 'textobjects')
            end, { desc = 'Select ' .. textobject })
          end
          add_select_keymap('aa', '@parameter.outer')
          add_select_keymap('ia', '@parameter.inner')
          add_select_keymap('al', '@loop.outer')
          add_select_keymap('il', '@loop.inner')
          add_select_keymap('af', '@function.outer')
          add_select_keymap('if', '@function.inner')
          add_select_keymap('ac', '@class.outer')
          add_select_keymap('ic', '@class.inner')
          add_select_keymap('ai', '@conditional.outer')
          add_select_keymap('ii', '@conditional.inner')
          add_select_keymap('gb', '@comment.outer')
          ---@param mapping string
          ---@param textobject string
          ---@param action 'goto_next_start'|'goto_next_end'|'goto_previous_start'|'goto_previous_end'
          local function set_move_keymap(mapping, textobject, action)
            vim.keymap.set({ 'n', 'x', 'o' }, mapping, function()
              require('nvim-treesitter-textobjects.move')[action](textobject, 'textobjects')
            end, { desc = action .. textobject })
          end
          set_move_keymap(']f', '@function.outer', 'goto_next_start')
          set_move_keymap(']c', '@class.outer', 'goto_next_start')
          set_move_keymap('[f', '@function.outer', 'goto_previous_start')
          set_move_keymap('[c', '@class.outer', 'goto_previous_start')
          set_move_keymap(']F', '@function.outer', 'goto_next_end')
          set_move_keymap(']C', '@class.outer', 'goto_next_end')
          set_move_keymap('[F', '@function.outer', 'goto_previous_end')
          set_move_keymap('[C', '@class.outer', 'goto_previous_end')
        end,
      },
    },
    build = ':TSUpdate',
    config = function()
      vim.treesitter.language.register('markdown', 'markdown.mdx')
      vim.treesitter.language.register('markdown', 'notify')
      vim.treesitter.language.register('markdown', 'octo')
    end,
  },
}
