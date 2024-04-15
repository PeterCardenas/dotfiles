M = {}

--- @deprecated gopls should be working with `bazel clean`
M.GOPLS_WORKAROUND_ENABLED = os.getenv("GOPLS_WORKAROUND") ~= nil

return M
