return {
  -- Language Server Protocol.
  {
    'neovim/nvim-lspconfig',
    lazy = false,
    config = function()
      require('tom.lsp')
    end
  },

  -- Languages.
  {
    'mrcjkb/rustaceanvim',
    dependencies = {
      'neovim/nvim-lspconfig',
    },
    config = function()
      vim.g.rustaceanvim = {
        server = {
          on_attach = require('tom.lsp').on_attach,
          capabilities = require('tom.lsp').capabilities,
        },
      }
    end,
    ft = { 'rust' },
  },
}
