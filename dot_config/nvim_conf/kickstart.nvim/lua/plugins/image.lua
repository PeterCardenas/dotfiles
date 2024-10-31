local image_ft = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'webp',
  'svg',
}

local image_patterns = vim
  .iter(image_ft)
  :map(function(ft)
    return string.format('*.%s', ft)
  end)
  :totable()

local lazy_load_patterns = vim.list_extend({
  '*.md',
  '*.mdx',
}, image_patterns)

local events = vim
  .iter(lazy_load_patterns)
  :map(function(pattern)
    return string.format('BufEnter %s', pattern)
  end)
  :totable()

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = image_patterns,
  callback = function(args)
    local buf = args.buf
    local win = vim.api.nvim_get_current_win()
    local path = vim.api.nvim_buf_get_name(buf)

    require('image').hijack_buffer(path, win, buf)
  end,
})

---@type LazyPluginSpec[]
return {
  -- Support viewing images.
  {
    '3rd/image.nvim',
    dependencies = {
      'leafo/magick',
    },
    event = events,
    cond = function()
      -- Nested tmux sessions are not supported.
      return vim.env.SSH_CONNECTION == nil or vim.env.TMUX == nil
    end,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('image').setup({
        integrations = {
          markdown = {
            filetypes = { 'markdown', 'vimwiki', 'markdown.mdx' },
          },
        },
        hijack_file_patterns = {},
      })
    end,
  },
}
