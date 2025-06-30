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

---@param type string
---@return string
function M.get_fre_store_name(type)
  local cwd = vim.fn.getcwd()
  local store_name = 'type:' .. type .. '::cwd:' .. cwd:gsub('[/() ]', '_') .. '.json'
  return store_name
end

-- TODO: share with rg_words_cmd
local function get_global_gitignore_flag()
  local home = os.getenv('HOME')
  local global_gitignore = home .. '/.config/git/ignore'
  return '--ignore-file=' .. global_gitignore
end

---@param show_ignore boolean
function M.rg_files_cmd(show_ignore)
  local rg_cmd = 'rg --files --color=never ' .. common_rg_args() .. (show_ignore and ' --no-ignore' or ' ' .. get_global_gitignore_flag())
  local fre_cmd = 'fre --sorted --store_name ' .. M.get_fre_store_name('files')
  -- De-duplicate results while live streaming results
  -- gstdbuf is only on macos, while stdbuf is on linux
  local stdbuf_cmd = ''
  local has_gstdbuf = vim.fn.executable('gstdbuf') == 1
  local has_stdbuf = vim.fn.executable('stdbuf') == 1

  if has_gstdbuf then
    stdbuf_cmd = 'gstdbuf -o0'
  elseif has_stdbuf then
    stdbuf_cmd = 'stdbuf -o0'
  else
    vim.notify_once('Neither gstdbuf nor stdbuf found. Output will be wholly buffered.', vim.log.levels.WARN)
    stdbuf_cmd = ''
  end

  if stdbuf_cmd ~= '' then
    stdbuf_cmd = stdbuf_cmd .. ' '
  end

  local cmd = '{ ' .. fre_cmd .. '; ' .. rg_cmd .. '; }' .. ' | ' .. stdbuf_cmd .. "awk '!seen[$0]++'"
  return cmd
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

function M.rg_words_opts()
  return '--hidden -g "!.git" --column --line-number --no-heading --color=always --smart-case --max-columns=4096 -e'
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
    -- TODO: Add show_ignore being true doesn't work here.
    require('fzf-lua.providers.grep').live_grep_glob({
      ---@type string
      rg_opts = M.rg_words_opts(),
      ---@type boolean
      no_ignore = show_ignore,
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
      -- HACK: similar to lazygit except this one works. When resuming the height is too small
      vim.defer_fn(
        vim.schedule_wrap(function()
          local fzfwin = require('fzf-lua.win').__SELF() ---@module "fzf-lua.win"
          local winid = fzfwin.fzf_winid
          local current_height = vim.api.nvim_win_get_height(winid)
          vim.api.nvim_win_set_height(winid, current_height - 5)
          vim.defer_fn(
            vim.schedule_wrap(function()
              vim.api.nvim_win_set_height(winid, current_height)
            end),
            20
          )
        end),
        20
      )
    end
  end)

  nmap('[F]ind [N]otification', 'fn', function()
    require('telescope').extensions.notify.notify()
    -- TODO: Errors with no notifications and enter does not open in a floating window
    -- require('noice.integrations.fzf').open()
  end)
end

return M
