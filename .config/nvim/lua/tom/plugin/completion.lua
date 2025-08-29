return {
  -- nvim-cmp
  {
    'hrsh7th/nvim-cmp',
    -- Load cmp on InsertEnter
    event = 'VeryLazy',
    config = function()
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
}
