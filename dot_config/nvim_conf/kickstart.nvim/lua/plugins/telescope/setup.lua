local M = {}

function M.find_recent_files()
  if require('utils.config').USE_TELESCOPE then
    require('telescope.builtin').oldfiles({ entry_maker = require('plugins.telescope.files_picker').make_files_entry() })
  else
    require('fzf-lua.providers.oldfiles').oldfiles()
  end
end

function M.find_files()
  if require('utils.config').USE_TELESCOPE then
    require('plugins.telescope.files_picker').find_files({ show_ignore = false })
  else
    require('fzf-lua.providers.files').files({
      cmd = 'rg --files --color=never --hidden -g "!.git"',
    })
  end
end

function M.find_words()
  if require('utils.config').USE_TELESCOPE then
    require('telescope').extensions.live_grep_args.live_grep_args()
  else
    require('fzf-lua.providers.grep').live_grep_glob_mt({
      cmd = 'rg --hidden -g "!.git"',
      git_icons = false,
      file_icons = false,
      path_shorten = false,
      formatter = false,
    })
  end
end

function M.create_keymaps()
  local nmap = require('utils.keymap').nmap

  nmap('[F]ind [O]ld files', 'fo', function()
    M.find_recent_files()
  end)

  nmap('[/] Fuzzily search in current buffer', '/', function()
    if require('utils.config').USE_TELESCOPE then
      require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown({
        winblend = 10,
        previewer = true,
        layout_config = {
          width = 0.8,
        },
      }))
    else
      require('fzf-lua.providers.buffers').blines({
        winopts = {
          backdrop = 60,
        },
      })
    end
  end)

  nmap('[F]ind b[u]ffers', 'fu', function()
    -- TODO: Convert custom telescope buffer picker to fzf-lua
    -- require('fzf-lua.providers.buffers').buffers({ ignore_current_file = true })
    require('plugins.telescope.buffer_picker').find_buffers()
  end)

  nmap('[F]ind [F]iles', 'ff', M.find_files)

  nmap('[F]ind Any [F]ile', 'fF', function()
    if require('utils.config').USE_TELESCOPE then
      require('plugins.telescope.files_picker').find_files({ show_ignore = true })
    else
      require('fzf-lua.providers.files').files({
        cmd = 'rg --files --hidden -g "!.git" --no-ignore',
      })
    end
  end)

  nmap('[F]ind [W]ords with ripgrep', 'fw', M.find_words)

  nmap('[F]ind [W]ords with ripgrep across all files', 'fW', function()
    if require('utils.config').USE_TELESCOPE then
      require('telescope.builtin').live_grep({
        additional_args = function(args)
          return vim.list_extend(args, { '--hidden', '--no-ignore' })
        end,
      })
    else
      require('fzf-lua.providers.grep').live_grep_native({
        cmd = 'rg --hidden -g "!.git" --no-ignore',
      })
    end
  end)

  nmap('[F]ind [H]elp', 'fh', function()
    if require('utils.config').USE_TELESCOPE then
      require('telescope.builtin').help_tags()
    else
      require('fzf-lua.providers.helptags').helptags()
    end
  end)

  nmap('[L]ist [D]iagnostics', 'lD', function()
    if require('utils.config').USE_TELESCOPE then
      require('telescope.builtin').diagnostics({ bufnr = nil, no_unlisted = false })
    else
      require('fzf-lua.providers.diagnostic').all()
    end
  end)

  nmap('[F]ind [R]resume', 'fr', function()
    if require('utils.config').USE_TELESCOPE then
      require('telescope.builtin').resume()
    else
      require('fzf-lua.core').fzf_resume()
    end
  end)

  nmap('[F]ind [N]otification', 'fn', function()
    require('telescope').extensions.notify.notify()
    -- TODO: Errors with no notifications and enter does not open in a floating window
    -- require('noice.integrations.fzf').open()
  end)
end

return M
