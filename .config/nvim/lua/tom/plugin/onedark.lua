return {
  {
    'navarasu/onedark.nvim',
    lazy = false,
    opts = {
      ending_tildes = true,
    },
    config = function()
      require('onedark').load()
      -- Keep Sidekick's terminal split on the editor background, not NormalFloat.
      vim.api.nvim_set_hl(0, 'SidekickChat', { link = 'Normal' })
    end,
  },
}
