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

local events = vim
  .iter(image_patterns)
  :map(function(pattern)
    return string.format('BufEnter %s', pattern)
  end)
  :totable()

table.insert(events, 'BufEnter *.md')

---@type LazyPluginSpec[]
return {
  -- Support viewing images.
  {
    '3rd/image.nvim',
    dependencies = {
      'leafo/magick',
    },
    event = events,
    config = function()
      ---@diagnostic disable-next-line: missing-fields
      require('image').setup({
        hijack_file_patterns = image_patterns,
      })
    end,
  },
}
