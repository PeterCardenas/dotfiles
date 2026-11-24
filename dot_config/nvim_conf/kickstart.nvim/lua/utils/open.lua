local M = {}

local function strip_trailing_punctuation(url)
  return (url:gsub([[['".,;:!%)%]}>]+$]], ''))
end

---@param cword string
---@param cfile string
---@return string
function M.resolve_gx_target(cword, cfile)
  -- TODO: Remove explicit URI detection after https://github.com/neovim/neovim/pull/40120 lands.
  local url = cword:match('([A-Za-z][A-Za-z0-9+.-]*://%S+)')
    or cword:match('(localhost:%d+%S*)')
    or cword:match('(%d+%.%d+%.%d+%.%d+:%d+%S*)')
    or cword:match('(%[[%x:]+%]:%d+%S*)')
  if not url then
    return cfile
  end

  url = strip_trailing_punctuation(url)
  return url:find('://', 1, true) and url or 'http://' .. url
end

---@param node TSNode
---@param child_type string
---@return TSNode?
local function find_child(node, child_type)
  for child in node:iter_children() do
    if child:type() == child_type then
      return child
    end
  end
  return nil
end

-- CommonMark matches reference labels case-insensitively with collapsed whitespace.
---@param label string
---@return string
local function normalize_reference_label(label)
  return vim.trim(label:gsub('^%[', ''):gsub('%]$', ''):gsub('%s+', ' ')):lower()
end

---@param bufnr integer
---@param label string
---@return TSNode?
local function find_reference_destination(bufnr, label)
  local block_tree = vim.treesitter.get_parser(bufnr, 'markdown', { error = false })
  if not block_tree then
    return nil
  end
  local query = vim.treesitter.query.parse('markdown', '(link_reference_definition (link_label) @label (link_destination) @destination)')
  local wanted = normalize_reference_label(label)
  for _, tree in ipairs(block_tree:trees()) do
    for _, match in query:iter_matches(tree:root(), bufnr) do
      local label_node, destination_node = match[1][1], match[2][1]
      if normalize_reference_label(vim.treesitter.get_node_text(label_node, bufnr)) == wanted then
        return destination_node
      end
    end
  end
  return nil
end

---@param bufnr integer
---@param link TSNode
---@return TSNode?
local function link_destination_node(bufnr, link)
  local link_type = link:type()
  if link_type == 'link_destination' then
    return link
  end
  if link_type == 'inline_link' or link_type == 'image' or link_type == 'link_reference_definition' then
    return find_child(link, 'link_destination')
  end
  local label = link_type == 'full_reference_link' and find_child(link, 'link_label') or find_child(link, 'link_text')
  if not label then
    return nil
  end
  return find_reference_destination(bufnr, vim.treesitter.get_node_text(label, bufnr))
end

local MARKDOWN_LINK_TYPES = {
  link_destination = true,
  inline_link = true,
  image = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
  link_reference_definition = true,
}

-- Markdown destinations are relative to the document, not Neovim's cwd.
---@param bufnr integer
---@param destination string
---@return string?
local function resolve_markdown_destination(bufnr, destination)
  destination = destination:gsub('^<(.*)>$', '%1')
  if destination:match('^[A-Za-z][A-Za-z0-9+.-]*:') then
    return destination
  end
  local path = destination:gsub('#.*$', '')
  -- In-document anchors have nothing to open externally.
  if path == '' then
    return nil
  end
  if vim.startswith(path, '/') or vim.startswith(path, '~') then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)), path))
end

---Resolves the markdown link or autolink under the cursor with treesitter.
---@return string?
function M.markdown_link_target()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr, nil, { error = false })
  if not parser then
    return nil
  end
  -- Reference links need the whole block tree and inline links need injections.
  parser:parse(true)

  local node = vim.treesitter.get_node({ bufnr = bufnr, ignore_injections = false })
  while node do
    local node_type = node:type()
    if node_type == 'uri_autolink' then
      return (vim.treesitter.get_node_text(node, bufnr):gsub('^<(.*)>$', '%1'))
    end
    if MARKDOWN_LINK_TYPES[node_type] then
      local destination = link_destination_node(bufnr, node)
      return destination and resolve_markdown_destination(bufnr, vim.treesitter.get_node_text(destination, bufnr))
    end
    node = node:parent()
  end
  return nil
end

function M.gx()
  local target = M.markdown_link_target() or M.resolve_gx_target(vim.fn.expand('<cWORD>'), vim.fn.expand('<cfile>'))
  local _, err = vim.ui.open(target)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end

---Open a file path, or a URL in the system's default application.
---Returns whether the operation was successful.
---@param uri string
---@param quiet? boolean
---@return boolean
function M.system_open(uri, quiet)
  quiet = quiet or false
  if vim.fn.empty(vim.fn.getenv('SSH_CONNECTION')) == 0 then
    if not quiet then
      vim.notify('system_open is not supported in SSH sessions', vim.log.levels.ERROR, { title = 'System Open' })
    end
    return false
  end
  if vim.fn.has('mac') == 1 then
    -- if mac use the open command
    vim.fn.jobstart({ 'open', uri }, { detach = true })
  elseif vim.fn.has('unix') == 1 then
    -- if unix then use xdg-open
    vim.fn.jobstart({ 'xdg-open', uri }, { detach = true })
  else
    if not quiet then
      vim.notify('System open is not supported on this OS!', vim.log.levels.ERROR, { title = 'System Open' })
    end
    return false
  end
  return true
end

return M
