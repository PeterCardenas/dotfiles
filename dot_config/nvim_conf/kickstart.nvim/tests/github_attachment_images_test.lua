vim.opt.rtp:prepend(vim.fn.getcwd())

vim.treesitter.query.add_directive('agentic-bash-tool-call-inject!', function() end, { force = true })
vim.treesitter.query.set('markdown_inline', 'images', '(image (link_destination) @image.src) @image')

local Images = require('utils.github_attachment_images')

local markdown_url = 'https://github.com/user-attachments/assets/demo'
local rendered_url = 'https://private-user-images.githubusercontent.com/demo?jwt=token'
local completed = false
local mappings

Images.extract({
  {
    md = '# Demo\n\n![recording](' .. markdown_url .. ')',
    html = '<h1>Demo</h1><p><img src="' .. rendered_url .. '"></p>',
  },
  { md = nil, html = nil },
}, function(result)
  mappings = result
  completed = true
end)

assert(not completed, 'extraction must yield before invoking its callback')
assert(
  vim.wait(5000, function()
    return completed
  end),
  'asynchronous extraction timed out'
)
assert(mappings[markdown_url] == rendered_url, 'rendered URL did not match the Markdown attachment')

print('github_attachment_images: ok')
