return {
  {
    "cbochs/grapple.nvim",
    opts = {
      icons = false,
    },
    keys = {
      { "<leader>t", "<cmd>Grapple toggle<cr>", desc = "Tag a file" },
      { "<leader>s", "<cmd>Grapple toggle_tags<cr>", desc = "Toggle tags menu" },

      { "<c-n>", "<cmd>Grapple select index=1<cr>", desc = "Select first tag" },
      { "<c-e>", "<cmd>Grapple select index=2<cr>", desc = "Select second tag" },
      { "<c-t>", "<cmd>Grapple select index=3<cr>", desc = "Select third tag" },
      { "<c-s>", "<cmd>Grapple select index=4<cr>", desc = "Select fourth tag" },
    },
  }
}
