-- Package sources for my nvim config
--
-- Uses lazy.nvim

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Load plugins defined in another file (if it exists).
local function local_plugins()
  local filename = vim.uv.os_homedir() .. '/.config/sysplugin.lua'
  if (vim.uv or vim.loop).fs_stat(filename) then
    return dofile(filename)
  end
end

return require('lazy').setup({
  spec = {
    -- Make sure that lazy manages itself.
    { 'folke/lazy.nvim' },

    -- Visual customization.
    --
    -- Colourscheme.
    {
      'navarasu/onedark.nvim',
      lazy = false,
      opts = {
        ending_tildes = true,
      },
      config = function()
        require('onedark').load()
      end,
    },
    -- Line
    {
      'nvim-lualine/lualine.nvim',
      event = 'VeryLazy', -- Allow lualine to come in late
      config = function()
          require('tom.lualine')
      end
    },

    -- Completion engine.
    --
    -- nvim-cmp
    {
      'hrsh7th/nvim-cmp',
      -- Load cmp on InsertEnter
      event = 'VeryLazy',
      config = function ()
        require('tom.completion')
      end,
      dependencies = {
        'hrsh7th/cmp-cmdline',
        'hrsh7th/cmp-path',
        'hrsh7th/cmp-buffer',
        'hrsh7th/cmp-nvim-lsp',
        'hrsh7th/cmp-nvim-lsp-document-symbol'
      },
    },
    -- Snippets.
    {
      'l3mon4d3/luasnip',
      event = 'InsertEnter',
      dependencies = {
        'hrsh7th/nvim-cmp',
        'saadparwaiz1/cmp_luasnip',
      },
    },

    -- AI completion.
    {
      'yetone/avante.nvim',
      event = 'InsertEnter',
      cmd = 'Avante',
      dependencies = {
        'nvim-treesitter/nvim-treesitter',
        'stevearc/dressing.nvim',
        'nvim-lua/plenary.nvim',
        'MunifTanjim/nui.nvim',
        'hrsh7th/nvim-cmp',
        'ravitemer/mcphub.nvim',
      },
      build = 'make',
      branch = 'main',
      config = function()
        require('tom.avante')
      end,
    },
    -- MCP
    {
      'ravitemer/mcphub.nvim',
      event = 'InsertEnter',
      cmd = 'MCPHub',
      dependencies = {
        'nvim-lua/plenary.nvim',
      },
      build = 'bundled_build.lua',  -- Installs `mcp-hub` node binary locally
      opts = {
        use_bundled_binary = true,  -- Use local `mcp-hub` binary
        auto_approve = true,
      },
    },

    -- Language Server Protocol.
    {
      'neovim/nvim-lspconfig',
      lazy = false,
      config = function ()
          require('tom.lsp')
      end
    },

    -- Highlights (tree-sitter).
    {
      'nvim-treesitter/nvim-treesitter',
      event = 'VeryLazy',
      config = function()
        require('tom.tree-sitter')
      end,
      build = ':TSUpdate'
    },

    -- Search.
    {
      'nvim-telescope/telescope.nvim',
      version = '0.1.8',
      event = 'VeryLazy',
      dependencies = {'nvim-lua/plenary.nvim'},
      opts = {
        defaults = {
          mappings = {
            i = {
              ["<esc>"] = "close"
            },
          },
        },
      },
    },

    -- Git integration.
    {
      'tpope/vim-fugitive',
      cmd = {
        'G', 'Git', 'Gstatus', 'Gblame',
        'Gpush', 'Gpull', 'Gedit',
      },
      ft = { 'gitcommit', 'gitrebase' },
      fn = { 'FugitiveHead' },
    },
    {
      'lewis6991/gitsigns.nvim',
      dependencies = {'nvim-lua/plenary.nvim'},
      opts = {},
    },

    -- Languages.
    {
      'mrcjkb/rustaceanvim',
      dependencies = {
        'neovim/nvim-lspconfig',
      },
      config = function ()
        vim.g.rustaceanvim = {
          server = {
            on_attach = require('tom.lsp').on_attach,
            capabilities = require('tom.lsp').capabilities,
          },
        }
      end,
      ft = { 'rust' },
    },
    {
      'lnl7/vim-nix',
      ft = { 'nix' },
    },
    {
      'kevinoid/vim-jsonc',
      ft = { 'jsonc' },
    },
    -- Obsidian
    {
      'epwalsh/obsidian.nvim',
      lazy = true,
      ft = { 'markdown' },
      version = '*',
      dependencies = {
        'nvim-lua/plenary.nvim',
      },
      config = function()
        require('tom.obsidian')
      end,
    },

    -- Load custom plugins.
    local_plugins()
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "onedark" } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  ui = {
    icons = {
      cmd = "⌘",
      config = "🛠",
      event = "📅",
      ft = "📂",
      init = "⚙",
      keys = "🗝",
      plugin = "🔌",
      runtime = "💻",
      require = "🌙",
      source = "📄",
      start = "🚀",
      task = "📌",
      lazy = "💤 ",
    },
  },
})
