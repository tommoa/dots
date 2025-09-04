return {
  {
    "cbochs/grapple.nvim",
    opts = {
      icons = false,
    },
    keys = {
      { "<leader>t", "<cmd>Grapple toggle<cr>", desc = "Tag a file" },
      { "<leader>s", "<cmd>Grapple toggle_tags<cr>", desc = "Toggle tags menu" },

      { "<c-n>", function() require('grapple').select({ index = 1 }) end, desc = "Select first tag" },
      { "<c-e>", function() require('grapple').select({ index = 2 }) end, desc = "Select second tag" },
      { "<c-t>", function() require('grapple').select({ index = 3 }) end, desc = "Select third tag" },
      { "<c-s>", function() require('grapple').select({ index = 4 }) end, desc = "Select fourth tag" },

      { "<leader><c-n>", function() require('grapple').select({ index = 1, command = vim.cmd.vsplit }) end, desc = "Select first tag" },
      { "<leader><c-e>", function() require('grapple').select({ index = 2, command = vim.cmd.vsplit }) end, desc = "Select second tag" },
      { "<leader><c-t>", function() require('grapple').select({ index = 3, command = vim.cmd.vsplit }) end, desc = "Select third tag" },
      { "<leader><c-s>", function() require('grapple').select({ index = 4, command = vim.cmd.vsplit }) end, desc = "Select fourth tag" },
    },
  }
}
