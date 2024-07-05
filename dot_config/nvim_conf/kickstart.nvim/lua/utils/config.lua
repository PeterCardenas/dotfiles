M = {}

--- @deprecated gopls should be working with `bazel clean`
M.GOPLS_WORKAROUND_ENABLED = os.getenv('GOPLS_WORKAROUND') ~= nil

M.USE_HEIRLINE = os.getenv('USE_HEIRLINE') ~= nil

M.USE_TABLINE = os.getenv('USE_TABLINE') ~= nil

M.USE_CLANGD = os.getenv('USE_CLANGD') ~= nil

M.USE_JEDI = os.getenv('USE_JEDI') ~= nil

return M
