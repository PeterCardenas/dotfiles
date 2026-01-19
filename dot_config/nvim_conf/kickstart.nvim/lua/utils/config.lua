M = {}

--- @deprecated gopls should be working with `bazel clean`
M.GOPLS_WORKAROUND_ENABLED = os.getenv('GOPLS_WORKAROUND') ~= nil

M.USE_HEIRLINE = os.getenv('USE_HEIRLINE') ~= nil

M.USE_TABLINE = os.getenv('USE_TABLINE') ~= nil

M.USE_CLANGD = os.getenv('USE_CLANGD') == nil

M.USE_JEDI = os.getenv('USE_JEDI') ~= nil

M.USE_SUPERMAVEN = os.getenv('USE_COPILOT') == nil

M.USE_TELESCOPE = os.getenv('USE_TELESCOPE') ~= nil

M.USE_RUST_LUA_LS = os.getenv('USE_RUST_LUA_LS') ~= nil

M.USE_SNACKS_PROFILER = os.getenv('USE_SNACKS_PROFILER') ~= nil

M.USE_BLINK_CMP = os.getenv('USE_LEGACY_CMP') == nil

M.USE_SNACKS_IMAGE = os.getenv('USE_IMAGE_NVIM') == nil

M.DISABLE_GOPACKAGESDRIVER = os.getenv('DISABLE_GOPACKAGESDRIVER') ~= nil

M.USE_LUA_LS_TIP = os.getenv('USE_LUA_LS_TIP') ~= nil

M.USE_ZUBAN = os.getenv('USE_ZUBAN') ~= nil

M.FZF_LUA_REPO = 'ibhagwan/fzf-lua'

return M
