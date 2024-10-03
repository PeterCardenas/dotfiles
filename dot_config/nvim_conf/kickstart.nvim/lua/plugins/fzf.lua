local function create_keymaps()
  local nmap = require('utils.keymap').nmap

  -- Telescope keymaps
  nmap('[F]ind [O]ld files', 'fo', function()
    require('fzf-lua.providers.oldfiles').oldfiles()
  end)

  nmap('[/] Fuzzily search in current buffer', '/', function()
    require('fzf-lua.providers.buffers').blines({
      winopts = {
        backdrop = 60,
      },
    })
  end)

  nmap('[F]ind b[u]ffers', 'fu', function()
    require('fzf-lua.providers.buffers').buffers({ ignore_current_file = true })
  end)

  nmap('[F]ind [F]iles', 'ff', function()
    require('fzf-lua.providers.files').files({
      cmd = 'rg --files --hidden',
    })
  end)

  nmap('[F]ind Any [F]ile', 'fF', function()
    require('fzf-lua.providers.files').files({
      cmd = 'rg --files --hidden --no-ignore',
    })
  end)

  nmap('[F]ind [W]ords with ripgrep', 'fw', function()
    require('fzf-lua.providers.grep').live_grep_native({
      cmd = 'rg --hidden',
    })
  end)

  nmap('[F]ind [W]ords with ripgrep across all files', 'fW', function()
    require('fzf-lua.providers.grep').live_grep_native({
      cmd = 'rg --hidden --no-ignore',
    })
  end)

  nmap('[F]ind [H]elp', 'fh', function()
    require('fzf-lua.providers.helptags').helptags()
  end)

  nmap('[L]ist [D]iagnostics', 'lD', function()
    require('fzf-lua.providers.diagnostic').all()
  end)

  nmap('[F]ind [R]resume', 'fr', function()
    require('fzf-lua.core').fzf_resume()
  end)

  nmap('[F]ind [N]otification', 'fn', function()
    require('noice.integrations.fzf').open()
  end)
end

if not require('utils.config').USE_TELESCOPE then
  create_keymaps()
end

---@type LazyPluginSpec[]
return {
  {
    'ibhagwan/fzf-lua',
    dependencies = {
      'echasnovski/mini.icons',
    },
    cmd = { 'FzfLua' },
    config = function()
      require('fzf-lua').setup({
        keymap = {
          builtin = {
            ['<C-D>'] = 'preview-page-down',
            ['<C-U>'] = 'preview-page-up',
          },
        },
      })
    end,
  },
}
