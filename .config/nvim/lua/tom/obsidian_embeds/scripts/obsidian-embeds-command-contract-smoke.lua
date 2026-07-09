-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-command-contract-smoke.lua

local test = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))
test.setup_runtime()

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.mkdir(root .. "/.obsidian", "p")
test.write_file(root .. "/Main.md", { "![[Target]]" })
test.write_file(root .. "/Target.md", { "target body" })

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    {
      name = "command-contract-smoke",
      path = root,
    },
  },
  picker = {
    name = false,
  },
  ui = {
    enable = false,
  },
}

require("tom.obsidian_embeds.contract").assert_obsidian()
require("obsidian").register_command("embeds", {
  nargs = "*",
  note_action = true,
  complete = function(arg_lead)
    return vim.tbl_filter(function(item)
      return vim.startswith(item, arg_lead)
    end, { "toggle", "refresh", "stats" })
  end,
})
vim.cmd.runtime("plugin/obsidian.lua")

vim.cmd.edit(root .. "/Main.md")
local bufnr = vim.api.nvim_get_current_buf()
vim.b[bufnr].obsidian_buffer = true

local embeds = require("tom.obsidian_embeds")
embeds.setup({ debounce_ms = 10 })
embeds.attach(bufnr)
embeds.refresh(bufnr)

local ns = vim.api.nvim_create_namespace(embeds.namespace)
test.assert_contains(test.rendered_text(bufnr, ns), "target body", "fixture should render before command checks")

vim.cmd("Obsidian embeds refresh")
test.assert_contains(test.rendered_text(bufnr, ns), "target body", "Obsidian embeds refresh should refresh the buffer")

vim.cmd("Obsidian embeds toggle")
test.assert_true(#vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true }) == 0, "Obsidian embeds toggle should disable and clear marks")

vim.cmd("Obsidian embeds toggle")
test.assert_contains(test.rendered_text(bufnr, ns), "target body", "Obsidian embeds toggle should re-enable rendering")

local completions = require("obsidian.commands").get_completions("", "Obsidian embeds ", #"Obsidian embeds ")
test.assert_true(vim.tbl_contains(completions, "toggle"), "embeds command should complete toggle")
test.assert_true(vim.tbl_contains(completions, "refresh"), "embeds command should complete refresh")
test.assert_true(vim.tbl_contains(completions, "stats"), "embeds command should complete stats")

local search = require("obsidian.search")
local original_resolve_note = search.resolve_note
search.resolve_note = nil
local ok, err = pcall(require("tom.obsidian_embeds.contract").assert_obsidian)
search.resolve_note = original_resolve_note
test.assert_true(not ok and tostring(err):find("obsidian.search.resolve_note", 1, true), "contract should name missing APIs")

print("obsidian embeds command/contract smoke test passed")
