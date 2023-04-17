--              AstroNvim Configuration Table
-- All configuration changes should go inside of the table below

-- You can think of a Lua "table" as a dictionary like data structure the
-- normal format is "key = value". These also handle array like data structures
-- where a value with no key simply has an implicit numeric key

local config = {
        -- Configure AstroNvim updates
        updater = {
                remote = "origin", -- remote to use
                channel = "nightly", -- "stable" or "nightly"
                version = "latest", -- "latest", tag name, or regex search like "v1.*" to only do updates before v2 (STABLE ONLY)
                branch = "main", -- branch name (NIGHTLY ONLY)
                commit = nil, -- commit hash (NIGHTLY ONLY)
                pin_plugins = nil, -- nil, true, false (nil will pin plugins on stable only)
                skip_prompts = false, -- skip prompts about breaking changes
                show_changelog = true, -- show the changelog after performing an update
                auto_reload = false, -- automatically reload and sync packer after a successful update
                auto_quit = false, -- automatically quit the current session after a successful update
                -- remotes = { -- easily add new remotes to track
                --   ["remote_name"] = "https://remote_url.come/repo.git", -- full remote url
                --   ["remote2"] = "github_user/repo", -- GitHub user/repo shortcut,
                --   ["remote3"] = "github_user", -- GitHub user assume AstroNvim fork
                -- },
        },
        -- Set colorscheme to use
        colorscheme = "sonokai",
        -- Add highlight groups in any theme
        highlights = {
                -- init = { -- this table overrides highlights in all themes
                --   Normal = { bg = "#000000" },
                -- }
                -- duskfox = { -- a table of overrides/changes to the duskfox theme
                --   Normal = { bg = "#000000" },
                -- },
        },
        icons = {
                VimIcon = "",
                ScrollText = "",
                GitBranch = "",
                GitAdd = "",
                GitChange = "",
                FileModified = "",
                GitDelete = "",
        },
        -- set vim options here (vim.<first_key>.<second_key> = value)
        options = {
                opt = {
                        -- set to true or false etc.
                        relativenumber = false, -- sets vim.opt.relativenumber
                        number = true, -- sets vim.opt.number
                        spell = false, -- sets vim.opt.spell
                        signcolumn = "auto", -- sets vim.opt.signcolumn to auto
                        wrap = false, -- sets vim.opt.wrap
                        shiftwidth = 2, -- tab level
                        tabstop = 2,
                        autoindent = true,
                        expandtab = true,
                        -- nvim-ufo setup
                        foldcolumn = "1",
                        foldlevel = 90,
                        foldenable = true,
                        fillchars = [[eob: ,fold: ,foldopen:,foldsep: ,foldclose:]],
                },

                g = {
                        -- sets vim.g.mapleader
                        mapleader = " ",
                        -- enable or disable auto formatting at start (lsp.formatting.format_on_save must be enabled)
                        autoformat_enabled = true,
                        -- enable completion at start
                        cmp_enabled = true,
                        -- enable autopairs at start
                        autopairs_enabled = true,
                        -- enable diagnostics at start
                        diagnostics_enabled = true,
                        -- enable diagnostics in statusline
                        status_diagnostics_enabled = true,
                        -- disable icons in the UI (disable if no nerd font is available, requires :PackerSync after changing)
                        icons_enabled = true,
                        -- disable notifications when toggling UI elements
                        ui_notifications_enabled = true,
                        -- enable new heirline based bufferline (requires :PackerSync after changing)
                        heirline_bufferline = true,
                        -- enables CamelCaseMotion package
                        camelcasemotion_key = "<leader>",
                        -- disables copilot warning for tab not be mapped
                        -- copilot_no_tab_map = true,
                        -- copilot_assume_mapped = true,
                        -- colorscheme config
                        sonokai_style = "shusia",
                        sonokai_better_performance = 1,
                        sonokai_enable_italic = 1,
                        sonokai_colors_override = { bg3 = { "#181a1c", "237" } },
                        sonokai_disable_italic_comment = 0,
                },
        },
        -- If you need more control, you can use the function()...end notation
        -- options = function(local_vim)
        --   local_vim.opt.relativenumber = true
        --   local_vim.g.mapleader = " "
        --   local_vim.opt.whichwrap = vim.opt.whichwrap - { 'b', 's' } -- removing option from list
        --   local_vim.opt.shortmess = vim.opt.shortmess + { I = true } -- add to option list
        --
        --   return local_vim
        -- end,

        -- Set dashboard header
        header = {
                " █████  ███████ ████████ ██████   ██████",
                "██   ██ ██         ██    ██   ██ ██    ██",
                "███████ ███████    ██    ██████  ██    ██",
                "██   ██      ██    ██    ██   ██ ██    ██",
                "██   ██ ███████    ██    ██   ██  ██████",
                " ",
                "    ███    ██ ██    ██ ██ ███    ███",
                "    ████   ██ ██    ██ ██ ████  ████",
                "    ██ ██  ██ ██    ██ ██ ██ ████ ██",
                "    ██  ██ ██  ██  ██  ██ ██  ██  ██",
                "    ██   ████   ████   ██ ██      ██",
        },
        -- Default theme configuration
        default_theme = {
                -- Modify the color palette for the default theme
                colors = {
                        fg = "#abb2bf",
                        bg = "#1e222a",
                },
                highlights = function(hl) -- or a function that returns a new table of colors to set
                        local C = require("default_theme.colors")

                        hl.Normal = { fg = C.fg, bg = C.bg }

                        -- New approach instead of diagnostic_style
                        hl.DiagnosticError.italic = true
                        hl.DiagnosticHint.italic = true
                        hl.DiagnosticInfo.italic = true
                        hl.DiagnosticWarn.italic = true

                        return hl
                end,
                -- enable or disable highlighting for extra plugins
                plugins = {
                        aerial = true,
                        beacon = false,
                        bufferline = true,
                        cmp = true,
                        dashboard = false,
                        highlighturl = true,
                        hop = false,
                        indent_blankline = true,
                        lightspeed = false,
                        ["neo-tree"] = true,
                        notify = true,
                        ["nvim-tree"] = false,
                        ["nvim-web-devicons"] = true,
                        rainbow = true,
                        symbols_outline = false,
                        telescope = true,
                        treesitter = true,
                        vimwiki = false,
                        ["which-key"] = true,
                },
        },
        -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
        diagnostics = {
                virtual_text = true,
                underline = true,
        },
        -- Extend LSP configuration
        lsp = {
                -- enable servers that you already have installed without mason
                servers = {
                        -- "pyright"
                },
                formatting = {
                        -- control auto formatting on save
                        format_on_save = {
                                enabled = true, -- enable or disable format on save globally
                                allow_filetypes = { -- enable format on save for specified filetypes only
                                        -- "go",
                                },
                                ignore_filetypes = { -- disable format on save for specified filetypes
                                        -- "python",
                                        -- temporarily ignored due to eslint fighting with prettier
                                        "javascript",
                                        "javascriptreact",
                                        "typescript",
                                        "typescriptreact",
                                        "lua",
                                        "yaml",
                                },
                        },
                        disabled = { -- disable formatting capabilities for the listed language servers
                                -- "sumneko_lua",
                                "tsserver",
                        },
                        timeout_ms = 1000, -- default format timeout
                        -- filter = function(client) -- fully override the default formatting function
                        --   return true
                        -- end
                },
                -- easily add or disable built in mappings added during LSP attaching
                mappings = {
                        n = {
                                ["<leader>lh"] = { "<cmd>lua vim.lsp.buf.hover()<cr>", desc = "Show LSP hover" },
                                ["<leader>lH"] = {
                                        "<cmd>lua vim.lsp.buf.signature_help()<cr>",
                                        desc = "Request LSP signature help",
                                },
                                -- ["<leader>lf"] = false -- disable formatting keymap
                        },
                        i = {
                                ["<C-s>"] = {
                                        "<cmd>lua vim.lsp.buf.signature_help()<cr>",
                                        desc = "Request LSP signature help",
                                },
                        },
                },
                -- add to the global LSP on_attach function
                -- on_attach = function(client, bufnr)
                -- end,

                -- override the mason server-registration function
                -- server_registration = function(server, opts)
                --   require("lspconfig")[server].setup(opts)
                -- end,

                -- Add overrides for LSP server settings, the keys are the name of the server
                ["server-settings"] = {
                        stylelint_lsp = {
                                filetypes = { "scss" },
                        },
                        clangd = {
                                filetypes = { "c", "cpp", "objc", "objcpp" },
                        },
                        -- example for addings schemas to yamlls
                        -- yamlls = { -- override table for require("lspconfig").yamlls.setup({...})
                        --   settings = {
                        --     yaml = {
                        --       schemas = {
                        --         ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*.{yml,yaml}",
                        --         ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
                        --         ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/*.{yml,yaml}",
                        --       },
                        --     },
                        --   },
                        -- },
                },
        },
        -- Mapping data with "desc" stored directly by vim.keymap.set().
        --
        -- Please use this mappings table to set keyboard mapping since this is the
        -- lower level configuration and more robust one. (which-key will
        -- automatically pick-up stored data by this setting.)
        mappings = {
                -- first key is the mode
                n = {
                        -- second key is the lefthand side of the map
                        -- mappings seen under group name "Buffer"
                        ["<leader>bb"] = { "<cmd>tabnew<cr>", desc = "New tab" },
                        -- Deprecated because of use of heirline_bufferline
                        -- ["<leader>bc"] = { "<cmd>BufferLinePickClose<cr>", desc = "Pick to close" },
                        -- ["<leader>bj"] = { "<cmd>BufferLinePick<cr>", desc = "Pick to jump" },
                        -- ["<leader>bt"] = { "<cmd>BufferLineSortByTabs<cr>", desc = "Sort by tabs" },
                        ["gj"] = { "<C-i>", desc = "Go to next location" },
                        ["gk"] = { "<C-o>", desc = "Go to previous location" },
                        ["<leader>gh"] = {
                                "<cmd>lua require'telescope.builtin'.git_stash()<cr>",
                                desc = "Open git stash previews",
                        },
                        ["<leader>bk"] = { "<cmd>bN<cr>", desc = "Go to previous buffer" },
                        ["<leader>bj"] = { "<cmd>bn<cr>", desc = "Go to next buffer" },
                        ["<leader>fw"] = {
                                "<cmd>lua require'telescope'.extensions.live_grep_args.live_grep_args()<cr>",
                                desc = "Find words in files",
                        },
                        -- Disable default vertical terminal mapping
                        ["<leader>tv"] = false,
                        ["<leader>ts"] = {
                                "<cmd>ToggleTerm size=55 direction=vertical<cr>",
                                desc = "Show vertical terminal",
                        },
                        -- Disable searching unnecessary things in favor of saving files
                        ["<leader>sb"] = false,
                        ["<leader>sc"] = false,
                        ["<leader>sh"] = false,
                        ["<leader>sk"] = false,
                        ["<leader>sm"] = false,
                        ["<leader>sn"] = false,
                        ["<leader>sr"] = false,
                        ["<leader>s"] = { "<cmd>w<cr>", desc = "Save file" },
                        ["<leader>x"] = { "<cmd>wqa<cr>", desc = "Save all buffers and quit all windows" },
                        -- nvim-ufo setup
                        ["zR"] = { "<cmd>lua require'ufo'openAllFolds()<cr>", desc = "Open all folds" },
                        ["zM"] = { "<cmd>lua require'ufo'closeAllFolds()<cr>", desc = "Close all folds" },
                        -- Fast tab swapping
                        ["<leader>rl"] = {
                                function()
                                        astronvim.move_buf(vim.v.count > 0 and vim.v.count or 1)
                                end,
                                desc = "Move buffer tab right",
                        },
                        ["<leader>rh"] = {
                                function()
                                        astronvim.move_buf(-(vim.v.count > 0 and vim.v.count or 1))
                                end,
                                desc = "Move buffer tab left",
                        },
                        -- quick save
                        -- ["<C-s>"] = { ":w!<cr>", desc = "Save File" },  -- change description but the same command
                },
                t = {
                        -- setting a mapping to false will disable it
                        -- Go to normal mode in a terminal
                },
                i = {
                        ["<C-BS>"] = { "<C-w>", desc = "Delete previous word" },
                        ["<M-BS>"] = { "<C-w>", desc = "Delete previous word" },
                },
        },
        -- Configure plugins
        plugins = {
                init = {
                        -- You can disable default plugins as follows:
                        -- ["goolord/alpha-nvim"] = { disable = true },

                        -- You can also add new plugins here as well:
                        -- Add plugins, the packer syntax without the "use"
                        -- { "andweeb/presence.nvim" },
                        -- {
                        --   "ray-x/lsp_signature.nvim",
                        --   event = "BufRead",
                        --   config = function()
                        --     require("lsp_signature").setup()
                        --   end,
                        -- },
                        -- Camel-case and snake-case motion
                        ["bkad/CamelCaseMotion"] = {},
                        -- Sticky scroll
                        ["nvim-treesitter/nvim-treesitter-context"] = {
                                config = function()
                                        require("treesitter-context").setup({
                                                mode = "topline",
                                                line_numbers = nil,
                                        })
                                end,
                        },
                        -- Colorscheme
                        ["sainnhe/sonokai"] = {},

                        -- Ripgrep with file name filtering
                        ["nvim-telescope/telescope-live-grep-args.nvim"] = {
                                after = "telescope.nvim",
                                config = function()
                                        require("telescope").load_extension("live_grep_args")
                                end,
                        },

                        -- Ripgrep with image/video/pdf preview, branched because of ueberzug being archived
                        ["HendrikPetertje/telescope-media-files.nvim"] = {
                                branch = "fix-replace-ueber-with-viu",
                                after = "telescope.nvim",
                                config = function()
                                        require("telescope").load_extension("media_files")
                                end,
                        },

                        -- Image viewer
                        ["princejoogie/chafa.nvim"] = {
                                requires = { "nvim-lua/plenary.nvim", "m00qek/baleia.nvim" },
                        },

                        -- Easy folding
                        ["kevinhwang91/nvim-ufo"] = {
                                requires = { "kevinhwang91/promise-async" },
                                config = function()
                                        require("ufo").setup({
                                                provider_selector = function()
                                                        return { "treesitter", "indent" }
                                                end,
                                        })
                                end,
                        },

                        -- Fast motion commands
                        ["ggandor/lightspeed.nvim"] = {
                                requires = { "tpope/vim-repeat" },
                        },

                        -- AI Autocomplete
                        ["github/copilot.vim"] = {},

                        -- We also support a key value style plugin definition similar to NvChad:
                        -- ["ray-x/lsp_signature.nvim"] = {
                        --   event = "BufRead",
                        --   config = function()
                        --     require("lsp_signature").setup()
                        --   end,
                        -- },
                },

                gitsigns = function(config)
                        config.current_line_blame = true
                        -- TODO: add github URL to blame
                        -- config.current_line_blame_formatter = function ()
                        -- end
                        config.current_line_blame_opts = {
                                delay = 100,
                        }
                        return config
                end,

                telescope = function(config)
                        config.extensions = {
                                media_files = {
                                        find_cmd = "rg",
                                        filetypes = { "png", "webm", "mp4" },
                                },
                        }
                        config.defaults.mappings.i["<C-v>"] = require("telescope.actions.layout").toggle_preview
                        config.defaults.mappings.n["<C-v>"] = require("telescope.actions.layout").toggle_preview
                        return config
                end,

                -- All other entries override the require("<key>").setup({...}) call for default plugins
                ["null-ls"] = function(config)
                        -- config variable is the default configuration table for the setup function call
                        local null_ls = require("null-ls")

                        -- Check supported formatters and linters
                        -- https://github.com/jose-elias-alvarez/null-ls.nvim/tree/main/lua/null-ls/builtins/formatting
                        -- https://github.com/jose-elias-alvarez/null-ls.nvim/tree/main/lua/null-ls/builtins/diagnostics
                        config.sources = {
                                null_ls.builtins.formatting.eslint_d.with({
                                        filetypes = {
                                                "typescript",
                                                "typescriptreact",
                                                "javascript",
                                                "javascriptreact",
                                        },
                                }),
                                null_ls.builtins.diagnostics.eslint_d.with({
                                        filetypes = {
                                                "typescript",
                                                "typescriptreact",
                                                "javascript",
                                                "javascriptreact",
                                        },
                                }),
                                null_ls.builtins.code_actions.eslint_d.with({
                                        filetypes = {
                                                "typescript",
                                                "typescriptreact",
                                                "javascript",
                                                "javascriptreact",
                                        },
                                }),
                                null_ls.builtins.formatting.prettierd.with({
                                        filetypes = {
                                                "typescript",
                                                "typescriptreact",
                                                "javascript",
                                                "javascriptreact",
                                                "yaml",
                                                "json",
                                        },
                                }),
                                null_ls.builtins.formatting.stylelint.with({
                                        filetypes = { "scss" },
                                }),
                        }
                        return config -- return final config table
                end,
                treesitter = { -- overrides `require("treesitter").setup(...)`
                        -- ensure_installed = { "lua" },
                },
                -- use mason-lspconfig to configure LSP installations
                ["mason-lspconfig"] = { -- overrides `require("mason-lspconfig").setup(...)`
                        -- ensure_installed = { "buf-language-server", "css-lsp", "eslint_d", "json-lsp", "lua-language-server", "pyright", "stylelint-lsp", "stylua", "taplo", "typescript-language-server" },
                },

                -- use mason-null-ls to configure Formatters/Linter installation for null-ls sources
                ["mason-null-ls"] = { -- overrides `require("mason-null-ls").setup(...)`
                        setup_handlers = {
                                -- eslint_d = function()
                                --     require("null-ls").register(require("null-ls").builtins.diagnostics.eslint_d.with {
                                --         condition = function(utils)
                                --             return utils.root_has_file "package.json"
                                --                 or utils.root_has_file ".eslintrc.json"
                                --                 or utils.root_has_file ".eslintrc.js"
                                --         end,
                                --     })
                                -- end,
                        },
                        -- ensure_installed = { "prettier", "stylua" },
                },
                ["mason-nvim-dap"] = { -- overrides `require("mason-nvim-dap").setup(...)`
                        -- ensure_installed = { "python" },
                },
                aerial = {
                        disable_max_size = 0,
                        disable_max_lines = 0,
                },

                heirline = function(config)
                        -- the first element of the default configuration table is the statusline
                        config[1] = {
                                -- set the fg/bg of the statusline
                                hl = { fg = "fg", bg = "bg" },
                                -- when adding the mode component, enable the mode text with padding to the left/right of it
                                astronvim.status.component.mode({ mode_text = { padding = { left = 1, right = 1 } } }),
                                -- add all the other components for the statusline
                                astronvim.status.component.git_branch(),
                                astronvim.status.component.git_diff(),
                                astronvim.status.component.diagnostics(),
                                -- File icon and file type
                                {
                                        astronvim.status.component.builder(astronvim.status.utils.setup_providers({
                                                file_icon = {
                                                        hl = astronvim.status.hl.file_icon("statusline"),
                                                        padding = { left = 1, right = 1 },
                                                },
                                                filetype = { padding = { right = 1 } },
                                        }, { "file_icon", "filetype" })),
                                },
                                -- Relative file path conditionally truncated
                                astronvim.status.component.fill(),
                                astronvim.status.component.cmd_info(),
                                astronvim.status.component.fill(),
                                astronvim.status.component.lsp(),
                                astronvim.status.component.treesitter(),
                                astronvim.status.component.nav(),
                        }

                        -- doesn't work with nvim-treesitter-context
                        config[2] = {
                                -- winbar
                                static = {
                                        disabled = {
                                                buftype = { "terminal", "prompt", "nofile", "help", "quickfix" },
                                                filetype = { "NvimTree", "neo%-tree", "dashboard", "Outline", "aerial" },
                                        },
                                },
                                init = function(self)
                                        self.bufnr = vim.api.nvim_get_current_buf()
                                end,
                                {
                                        condition = function(self)
                                                return vim.opt.diff:get() or
                                                    astronvim.status.condition.buffer_matches(self.disabled or {})
                                        end,
                                        init = function()
                                                vim.opt_local.winbar = nil
                                        end,
                                },
                                astronvim.status.component.file_info({
                                        file_icon = false,
                                        filetype = false,
                                        file_modified = false,
                                        filename = { modify = ":." },
                                        hl = astronvim.status.hl.get_attributes("winbarnc", true),
                                        padding = { left = 2 },
                                        surround = false,
                                }),
                                astronvim.status.component.breadcrumbs({
                                        hl = astronvim.status.hl.get_attributes("winbar", true),
                                }),
                        }

                        config[3] = { -- bufferline
                                { -- file tree padding
                                        condition = function(self)
                                                self.winid = vim.api.nvim_tabpage_list_wins(0)[1]
                                                return astronvim.status.condition.buffer_matches(
                                                        { filetype = { "neo%-tree", "NvimTree" } },
                                                        vim.api.nvim_win_get_buf(self.winid)
                                                )
                                        end,
                                        provider = function(self)
                                                return string.rep(" ", vim.api.nvim_win_get_width(self.winid))
                                        end,
                                        hl = { bg = "tabline_bg" },
                                },
                                -- component for each buffer tab
                                astronvim.status.heirline.make_buflist(astronvim.status.component.tabline_file_info()),
                                -- fill the rest of the tabline with background color
                                astronvim.status.component.fill({ hl = { bg = "tabline_bg" } }),
                                -- tab list
                                {
                                        -- only show tabs if there are more than one
                                        condition = function()
                                                return #vim.api.nvim_list_tabpages() >= 2
                                        end,
                                        -- create components for each tab page
                                        astronvim.status.heirline.make_tablist({ -- component for each tab
                                                provider = astronvim.status.provider.tabnr(),
                                                hl = function(self)
                                                        return astronvim.status.hl.get_attributes(
                                                                astronvim.status.heirline.tab_type(self, "tab"),
                                                                true
                                                        )
                                                end,
                                        }),
                                        -- close button for current tab
                                        {
                                                provider = astronvim.status.provider.close_button({
                                                        kind = "TabClose",
                                                        padding = { left = 1, right = 1 },
                                                }),
                                                hl = astronvim.status.hl.get_attributes("tab_close", true),
                                                on_click = {
                                                        callback = astronvim.close_tab,
                                                        name = "heirline_tabline_close_tab_callback",
                                                },
                                        },
                                },
                        }

                        -- return the final configuration table
                        return config
                end,

                session_manager = {
                        autoload_mode = require("session_manager.config").AutoloadMode.CurrentDir,
                        autosave_ignore_dirs = { "~/", "~/Downloads", "/" },
                },
        },
        -- LuaSnip Options
        luasnip = {
                -- Extend filetypes
                filetype_extend = {
                        -- javascript = { "javascriptreact" },
                },
                -- Configure luasnip loaders (vscode, lua, and/or snipmate)
                vscode = {
                        -- Add paths for including more VS Code style snippets in luasnip
                        paths = {},
                },
        },
        -- CMP Source Priorities
        -- modify here the priorities of default cmp sources
        -- higher value == higher priority
        -- The value can also be set to a boolean for disabling default sources:
        -- false == disabled
        -- true == 1000
        cmp = {
                source_priority = {
                        nvim_lsp = 1000,
                        luasnip = 750,
                        buffer = 500,
                        path = 250,
                },
        },
        -- Customize Heirline options
        heirline = {
                -- -- Customize different separators between sections
                -- separators = {
                --   tab = { "", "" },
                -- },
                -- -- Customize colors for each element each element has a `_fg` and a `_bg`
                -- colors = function(colors)
                --   colors.git_branch_fg = astronvim.get_hlgroup "Conditional"
                --   return colors
                -- end,
                -- -- Customize attributes of highlighting in Heirline components
                -- attributes = {
                --   -- styling choices for each heirline element, check possible attributes with `:h attr-list`
                --   git_branch = { bold = true }, -- bold the git branch statusline component
                -- },
                -- -- Customize if icons should be highlighted
                -- icon_highlights = {
                --   breadcrumbs = false, -- LSP symbols in the breadcrumbs
                --   file_icon = {
                --     winbar = false, -- Filetype icon in the winbar inactive windows
                --     statusline = true, -- Filetype icon in the statusline
                --   },
                -- },
        },
        -- Modify which-key registration (Use this with mappings table in the above.)
        ["which-key"] = {
                -- Add bindings which show up as group name
                register = function(config)
                        local new_config = astronvim.default_tbl({
                                -- first key is the mode, n == normal mode
                                n = {
                                        -- second key is the prefix, <leader> prefixes
                                        ["<leader>"] = {
                                                -- third key is the key to bring up next level and its displayed
                                                -- group name in which-key top level menu
                                                ["b"] = { name = "Buffer" },
                                                ["s"] = nil,
                                        },
                                },
                        }, config)
                        return new_config
                end,
        },
        -- This function is run last and is a good place to configuring
        -- augroups/autocommands and custom filetypes also this just pure lua so
        -- anything that doesn't fit in the normal config locations above can go here
        polish = function()
                require("chafa").setup({
                        render = {
                                min_padding = 5,
                                show_label = true,
                        },
                        events = {
                                update_on_nvim_resize = true,
                        },
                })
                -- vim.api.nvim_set_keymap("i", "<C-CR>", 'copilot#Accept("<CR>")', { silent = true, expr = true })

                -- Set up custom filetypes
                -- vim.filetype.add {
                --   extension = {
                --     foo = "fooscript",
                --   },
                --   filename = {
                --     ["Foofile"] = "fooscript",
                --   },
                --   pattern = {
                --     ["~/%.config/foo/.*"] = "fooscript",
                --   },
                -- }
        end,
}

return config
