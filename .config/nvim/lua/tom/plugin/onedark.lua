return {
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
}
