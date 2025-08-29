return {
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
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {},
  },
}
