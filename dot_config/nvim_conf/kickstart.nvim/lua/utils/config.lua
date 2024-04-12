M = {}

M.GOPLS_WORKAROUND_ENABLED = os.getenv("GOPLS_WORKAROUND") ~= nil

return M
