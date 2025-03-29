local Config = require('utils.config')
local FilePicker = require('plugins.telescope.files_picker')
local BufferPicker = require('plugins.telescope.buffer_picker')

local M = {}

function M.find_recent_files()
  if Config.USE_TELESCOPE then
    require('telescope.builtin').oldfiles({ entry_maker = FilePicker.make_files_entry() })
  else
    require('fzf-lua.providers.oldfiles').oldfiles()
  end
end

local function common_rg_args()
  -- TODO Share with rg_words_cmd
  return '--hidden -g "!.git" -g "!.mypy_cache" -g "!.ccls_cache"'
end

---@param show_ignore boolean
function M.rg_files_cmd(show_ignore)
  return 'rg --files --color=never ' .. common_rg_args() .. (show_ignore and ' --no-ignore' or '')
end

---@param show_ignore boolean
function M.find_files(show_ignore)
  if Config.USE_TELESCOPE then
    FilePicker.find_files({ show_ignore = show_ignore })
  else
    require('fzf-lua.providers.files').files({
      ---@type string
      cmd = M.rg_files_cmd(show_ignore),
    })
  end
end

---@param show_ignore boolean
function M.rg_words_cmd(show_ignore)
  return 'rg --hidden -g "!.git" --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e'
    .. (show_ignore and ' --no-ignore' or '')
end

---@param show_ignore boolean
function M.find_words(show_ignore)
  if Config.USE_TELESCOPE then
    require('telescope').extensions.live_grep_args.live_grep_args({
      additional_args = function(args)
        local additional_args = vim.list_extend({ '--hidden' }, args)
        if show_ignore then
          additional_args[#additional_args + 1] = '--no-ignore'
        end
        return additional_args
      end,
    })
  else
    require('fzf-lua.providers.grep').live_grep_glob({
      ---@type string
      cmd = M.rg_words_cmd(show_ignore),
    })
  end
end

function M.create_keymaps()
  local nmap = require('utils.keymap').nmap

  nmap('[F]ind [O]ld files', 'fo', function()
    M.find_recent_files()
  end)

  nmap('[/] Fuzzily search in current buffer', '/', function()
    if Config.USE_TELESCOPE then
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
    BufferPicker.find_buffers()
  end)

  nmap('[F]ind [F]iles', 'ff', function()
    M.find_files(false)
  end)

  nmap('[F]ind Any [F]ile', 'fF', function()
    M.find_files(true)
  end)

  nmap('[F]ind [W]ords with ripgrep', 'fw', function()
    M.find_words(false)
  end)

  nmap('[F]ind [W]ords with ripgrep across all files', 'fW', function()
    M.find_words(true)
  end)

  nmap('[F]ind [H]elp', 'fh', function()
    if Config.USE_TELESCOPE then
      require('telescope.builtin').help_tags()
    else
      require('fzf-lua.providers.helptags').helptags()
    end
  end)

  nmap('[L]ist [D]iagnostics', 'lD', function()
    if Config.USE_TELESCOPE then
      require('telescope.builtin').diagnostics({ bufnr = nil, no_unlisted = false })
    else
      require('fzf-lua.providers.diagnostic').all()
    end
  end)

  nmap('[F]ind [R]resume', 'fr', function()
    if Config.USE_TELESCOPE then
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
