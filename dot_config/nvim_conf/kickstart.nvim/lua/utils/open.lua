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

function M.gx()
  local target = M.resolve_gx_target(vim.fn.expand('<cWORD>'), vim.fn.expand('<cfile>'))
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
