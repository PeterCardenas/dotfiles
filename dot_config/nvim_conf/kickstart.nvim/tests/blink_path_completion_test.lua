local root = vim.fn.getcwd() .. '/dot_config/nvim_conf/kickstart.nvim'
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/blink.cmp')

-- Capture the real plugin options without starting the rest of the editor.
local options
package.loaded['blink.cmp'] = {
  setup = function(config)
    options = config
  end,
}
for _, plugin in ipairs(dofile(root .. '/lua/plugins/cmp.lua')) do
  if plugin[1] == 'saghen/blink.cmp' then
    plugin.config()
  end
end
assert(options, 'Blink configuration was not loaded')
local providers = options.sources.providers
assert(providers.path.transform_items, 'missing insert-mode path matching transform')
assert(providers.cmdline and providers.cmdline.transform_items, 'missing cmdline path matching transform')

local fuzzy = require('blink.cmp.fuzzy.rust')
local path_lib = require('blink.cmp.sources.path.lib')
local kinds = require('blink.cmp.types').CompletionItemKind
local line = '"./apps_platform/plat'
local context = { line = line, cursor = { 1, #line } }
local ranges = path_lib.get_text_edit_ranges(context)
local directory = path_lib.entry_to_completion_item(
  { name = 'platform', type = 'directory' },
  '/repo/apps_platform',
  ranges.directory,
  { trailing_slash = true, label_trailing_slash = true }
)
local original = vim.deepcopy(directory)
providers.path.transform_items(context, { directory })
assert(directory.filterText == 'platform', 'directory matching still includes its trailing slash')
local preserved = vim.deepcopy(directory)
preserved.filterText = original.filterText
assert(vim.deep_equal(preserved, original), 'directory label, insertion, or edit range changed')
local range = directory.textEdit.range
assert(range.start.character == #'"./apps_platform/', 'edit starts before the current path segment')
assert(
  line:sub(1, range.start.character) .. directory.textEdit.newText .. line:sub(range['end'].character + 1) == '"./apps_platform/platform/',
  'acceptance rewrites the preceding directory or drops the slash'
)

local function matches(query, item)
  fuzzy.set_provider_items('path-regression', { item })
  local _, indices = fuzzy.fuzzy(query, #query, { 'path-regression' }, { max_typos = 0, match_suffix = false })
  return #indices == 1
end
for _, query in ipairs({
  'e apps_platform/plat',
  'e apps_platform/ptfm',
  '"./apps_platform/plat',
  '"./agent-platform/plat',
  '"./space dir/apps_platform/plat',
}) do
  assert(not matches(query, original), 'baseline must reproduce the repeated-parent matching bug')
  assert(matches(query, directory), 'normalized directory is missing for ' .. query)
end

local cmdline_item = { label = 'platform/', filterText = 'platform/', textEdit = { newText = 'apps_platform/platform/' } }
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'e apps_platform/plat' })
local cmdline_context = { mode = 'cmdwin', line = 'e apps_platform/plat' }
providers.cmdline.transform_items(cmdline_context, { cmdline_item })
assert(cmdline_item.filterText == 'platform', 'cmdline directory matching still includes its slash')
assert(cmdline_item.label == 'platform/', 'cmdline directory label changed')
assert(cmdline_item.textEdit.newText == 'apps_platform/platform/', 'cmdline directory insertion changed')

vim.api.nvim_create_user_command('BlinkPathTest', function() end, {
  nargs = '*',
  complete = function()
    return { 'scope/' }
  end,
})
local custom_line = 'BlinkPathTest scope/'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { custom_line })
local custom_item = { label = 'scope/', filterText = 'scope/' }
providers.cmdline.transform_items({ mode = 'cmdwin', line = custom_line }, { custom_item })
assert(custom_item.filterText == 'scope/', 'non-path custom completion was changed')
local file = { label = 'file.txt', kind = kinds.File }
providers.path.transform_items(context, { file })
assert(file.filterText == nil, 'file matching was changed')
print('blink_path_completion: ok (Rust red/green, both providers, edit preservation, non-path guard)')
