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
    config = function ()
      local telescope = require('telescope.builtin')
      vim.keymap.set('n', 'zf', telescope.find_files)
      vim.keymap.set('n', 'zb', telescope.buffers)
      vim.keymap.set('n', '<leader>en', function ()
          telescope.find_files({
              cwd = vim.fn.stdpath('config'),
              no_ignore = true,
          })
      end)
    end,
  },
}
