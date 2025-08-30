return {
  {
    'nvim-treesitter/nvim-treesitter',
    config = function()
      require('nvim-treesitter.configs').setup {
        ensure_installed = {
          "bash",
          "c",
          "cpp",
          "python",
          "vim",
          "lua",
          "markdown",
          "markdown_inline",
          "rust",
          "nix",
          "css",
          "html",
          "gitcommit",
          "gitignore",
          "git_config",
          "git_rebase",
          "gitattributes",
        },
        ignore_install = {
          "ipkg",
          "norg",
        },
        auto_install = true, -- install parsers if missing when entering a buffer.
        sync_install = false,
        highlight = {
          -- Treesitter doesn't have 32-bit binaries.
          enable = vim.uv.os_uname().machine ~= "i686",
          disable = {},
        },
        indent = {
          -- Treesitter doesn't have 32-bit binaries.
          enable = vim.uv.os_uname().machine ~= "i686",
          disable = {},
        },
      }
    end,
    build = ':TSUpdate'
  },
}
