local function is_work_machine()
  if vim.uv.fs_stat('/src/') then
    -- Machines at my work tend to have a `/src/` directory.
    return true
  end
  return false
end

local codex_re = vim.regex("\\<codex\\>")

local function is_lcodex_proc(proc)
  return proc.env and proc.env.SIDEKICK_TOOL == "lcodex"
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
          codex = {
            is_proc = function(_, proc)
              return not is_lcodex_proc(proc) and codex_re:match_str(proc.cmd) ~= nil
            end,
          },
          lcodex = {
            cmd = { "lcodex" },
            env = { SIDEKICK_TOOL = "lcodex" },
            is_proc = function(_, proc)
              return is_lcodex_proc(proc)
            end,
            resume = { "resume" },
            continue = { "resume", "--last" },
          },
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
        "<leader>ac",
        function()
          require("sidekick.cli").toggle({ name = "codex", focus = true })
        end,
        desc = "Toggle the CLI (ai toggle)",
      },
      {
        "<leader>al",
        function()
          require("sidekick.cli").toggle({ name = "lcodex", focus = true })
        end,
        desc = "Toggle the local Codex CLI (ai toggle)",
      },
      {
        "<leader>as",
        function()
          require("sidekick.cli").toggle({ name = "opencode", focus = true })
        end,
        desc = "Toggle the CLI (ai toggle)",
      },
      {
        "<leader>ap",
        function()
          require("sidekick.cli").toggle({ name = "pi", focus = true })
        end,
        desc = "Toggle the CLI (ai toggle)",
      },
    },
  },
}
