local Config = require('utils.config')

local image_ft = {
  'png',
  'jpg',
  'jpeg',
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

---@type LazyPluginSpec[]
return {
  -- Support viewing images.
  {
    '3rd/image.nvim',
    event = events,
    cond = function()
      -- Nested tmux sessions are not supported.
      return (vim.env.SSH_CONNECTION == nil or vim.env.TMUX == nil) and not Config.USE_SNACKS_IMAGE
    end,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('image').setup({
        processor = 'magick_cli',
        tmux_show_only_in_active_window = true,
        integrations = {
          markdown = {
            filetypes = { 'markdown', 'vimwiki', 'markdown.mdx' },
            -- TODO: Use popup whenever this gets merged: https://github.com/3rd/image.nvim/pull/208
            -- Or use snacks.nvim whenever I get to it 🤷
            only_render_image_at_cursor = true,
          },
        },
        hijack_file_patterns = image_patterns,
      })
    end,
  },
}
