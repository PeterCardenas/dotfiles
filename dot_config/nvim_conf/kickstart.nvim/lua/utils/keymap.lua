local M = {}

---Declare a normal keymap
---@param name string Description of the keymap
---@param key string This keymap is prefixed with `<leader>`
---@param action_fn fun(): nil What to do when the keymap is triggered
function M.nmap(name, key, action_fn)
  vim.keymap.set('n', '<leader>' .. key, action_fn, { desc = name })
end

return M
