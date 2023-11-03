local chezmoi_augroup = vim.api.nvim_create_augroup("Chezmoi", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
  callback = function(args)
    local bufnr = args.buf
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if not filepath:find("^" .. os.getenv("HOME") .. "/.local/share/chezmoi") then
      return
    end
    vim.system({ "chezmoi", "apply", "--source-path", filepath })
  end,
  group = chezmoi_augroup,
  pattern = "*",
})

local function track_lazy_lock()
  local symlinked_lazy_lock_file_path = os.getenv("HOME") .. "/.config/nvim/lazy-lock.json"
  local lazy_lock_file_path_unformatted = vim.system({ "realpath", symlinked_lazy_lock_file_path }):wait()
      .stdout
  if not lazy_lock_file_path_unformatted then
    vim.notify("lazy-lock.json not found" .. symlinked_lazy_lock_file_path, vim.log.levels.ERROR)
    return
  end
  local lazy_lock_file_path = lazy_lock_file_path_unformatted:gsub("\n", "")
  local chezmoi_add_metadata = vim.system({ "chezmoi", "add", lazy_lock_file_path }):wait()
  if chezmoi_add_metadata.code ~= 0  then
    vim.notify("chezmoi add failed: " .. chezmoi_add_metadata.stderr, vim.log.levels.ERROR)
    return
  end
end

vim.api.nvim_create_autocmd("User", {
  callback = track_lazy_lock,
  group = chezmoi_augroup,
  pattern = { "LazyInstall", "LazyUpdate", "LazyClean" }
})
