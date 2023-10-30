vim.api.nvim_create_autocmd("BufWritePost", {
  callback = function(args)
    local bufnr = args.buf
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if not filepath:find("^" .. os.getenv("HOME") .. "/.local/share/chezmoi") then
      return
    end
    vim.system({ "chezmoi", "apply", "--source-path", filepath })
  end,
  group = vim.api.nvim_create_augroup("ChezmoiApply", { clear = true }),
  pattern = "*",
})
