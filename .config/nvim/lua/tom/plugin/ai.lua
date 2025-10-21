local function is_work_machine()
  if vim.uv.fs_stat('/src/') then
    -- Machines at my work tend to have a `/src/` directory.
    return true
  end
  return false
end

return {
  {
    'folke/sidekick.nvim',
    lazy = false,
    opts = {
      signs = { enabled = false },
      nes = {
        enabled = function(buf)
          if is_work_machine() then
             -- On work machines, bail.
             return false
          end
          return vim.g.sidekick_nes ~= false and vim.b.sidekick_nes ~= false
        end,
      },
      cli = {
        mux = {
          backend = "tmux",
          enabled = true,
        },
        tools = {
          opencode = { cmd = { "nix", "run", "nixpkgs/nixpkgs-unstable#opencode" } },
        },
      },
    },
    keys = {
      {
        "<leader>y", -- sidekick suggests <tab>, but that maps to C-i in the terminal (jump to next item)
        function()
          require("sidekick").nes_jump_or_apply()
        end,
        desc = "Goto/Apply Next Edit Suggestion",
      },
      {
        "<leader>at",
        function()
          require("sidekick.cli").toggle({ name = "opencode", focus = true })
        end,
        desc = "Toggle the CLI (ai toggle)",
      },
    },
  },
  {
    "zbirenbaum/copilot.lua",
    opts = {
      should_attach = function(_, buf)
        if is_work_machine() then
          -- On work machines, bail.
          return false
        end
        return true
      end,
    },
  },
}
