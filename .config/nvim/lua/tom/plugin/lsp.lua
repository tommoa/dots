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
    branch = 'main',
    dependencies = {
      'neovim/nvim-lspconfig',
    },
    ft = { 'rust' },
  },
}
