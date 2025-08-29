return {
  -- Search.
  {
    'nvim-telescope/telescope.nvim',
    version = '0.1.8',
    event = 'VeryLazy',
    dependencies = { 'nvim-lua/plenary.nvim' },
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
}
