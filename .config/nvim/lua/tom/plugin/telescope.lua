return {
  -- Search.
  {
    'nvim-telescope/telescope.nvim',
    version = '0.1.8',
    event = 'VeryLazy',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make'
      },
    },
    opts = {
      defaults = {
        mappings = {
          i = {
            ["<esc>"] = "close"
          },
        },
      },
      pickers = {
        find_files = {
          theme = "ivy",
        },
      },
      extensions = {
        fzf = {},
      },
    },
    keys = {
      { "zf", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "zb", "<cmd>Telescope buffers<cr>", desc = "List buffers" },
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>en", function()
        require('telescope.builtin').find_files({
          cwd = vim.fn.stdpath('config'),
          no_ignore = true,
        })
      end, desc = "Find files in nvim config" },
    },
  },
}
