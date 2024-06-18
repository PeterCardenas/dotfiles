M = {}

--- @deprecated gopls should be working with `bazel clean`
M.GOPLS_WORKAROUND_ENABLED = os.getenv('GOPLS_WORKAROUND') ~= nil

M.USE_HEIRLINE = os.getenv('USE_HEIRLINE') ~= nil

M.USE_CLANGD = os.getenv('USE_CLANGD') ~= nil

return M
