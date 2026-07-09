-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-workspace-smoke.lua

local test = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))
test.setup_runtime()

local root = vim.fn.tempname()
local vault_a = root .. "/A"
local vault_b = root .. "/B"
vim.fn.mkdir(vault_a .. "/.obsidian", "p")
vim.fn.mkdir(vault_b .. "/.obsidian", "p")
test.write_file(vault_a .. "/Main.md", { "![[SharedName]]", "![[CreatedLater]]" })
test.write_file(vault_b .. "/Main.md", { "![[SharedName]]", "![[CreatedLater]]" })
test.write_file(vault_a .. "/SharedName.md", { "workspace A shared" })
test.write_file(vault_b .. "/SharedName.md", { "workspace B shared" })

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    {
      name = "workspace-a",
      path = vault_a,
    },
    {
      name = "workspace-b",
      path = vault_b,
    },
  },
  picker = {
    name = false,
  },
  ui = {
    enable = false,
  },
}

local tracker = require("tom.obsidian_embeds.tracker")
tracker.reset()

local embeds = require("tom.obsidian_embeds")
embeds.setup({ debounce_ms = 10 })
local ns = vim.api.nvim_create_namespace(embeds.namespace)

-- Scenario: dependency and unresolved indexes are keyed by workspace root, so
-- matching note names in different vaults do not refresh or render each other.
vim.cmd.edit(vault_a .. "/Main.md")
local a_bufnr = vim.api.nvim_get_current_buf()
vim.b[a_bufnr].obsidian_buffer = true
embeds.attach(a_bufnr)
embeds.refresh(a_bufnr)

vim.cmd.edit(vault_b .. "/Main.md")
local b_bufnr = vim.api.nvim_get_current_buf()
vim.b[b_bufnr].obsidian_buffer = true
embeds.attach(b_bufnr)
embeds.refresh(b_bufnr)

test.assert_contains(test.rendered_text(a_bufnr, ns), "workspace A shared", "workspace A should render its own SharedName")
test.assert_contains(test.rendered_text(b_bufnr, ns), "workspace B shared", "workspace B should render its own SharedName")
test.assert_contains(test.rendered_text(a_bufnr, ns), "Embed not found: CreatedLater", "workspace A missing fixture should render warning")
test.assert_contains(test.rendered_text(b_bufnr, ns), "Embed not found: CreatedLater", "workspace B missing fixture should render warning")

vim.cmd.edit(vault_a .. "/CreatedLater.md")
vim.b[vim.api.nvim_get_current_buf()].obsidian_buffer = true
vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { "created later in workspace A" })
vim.cmd.write()
local a_refreshed = vim.wait(1000, function()
  return test.rendered_text(a_bufnr, ns):find("created later in workspace A", 1, true) ~= nil
end, 20)
test.assert_true(a_refreshed, "creating a missing note in workspace A should refresh workspace A dependents")
test.assert_true(
  not test.rendered_text(b_bufnr, ns):find("created later in workspace A", 1, true),
  "creating a note in workspace A should not refresh workspace B unresolved refs"
)
test.assert_contains(test.rendered_text(b_bufnr, ns), "Embed not found: CreatedLater", "workspace B should remain unresolved")

vim.cmd.edit(vault_b .. "/SharedName.md")
vim.b[vim.api.nvim_get_current_buf()].obsidian_buffer = true
vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { "workspace B shared changed" })
vim.cmd.write()
local b_refreshed = vim.wait(1000, function()
  return test.rendered_text(b_bufnr, ns):find("workspace B shared changed", 1, true) ~= nil
end, 20)
test.assert_true(b_refreshed, "editing workspace B target should refresh workspace B dependents")
test.assert_true(
  not test.rendered_text(a_bufnr, ns):find("workspace B shared changed", 1, true),
  "editing workspace B target should not alter workspace A dependents"
)

tracker.reset()
local stats = tracker.stats()
test.assert_true(stats.buffers == 0 and stats.path_keys == 0 and stats.unresolved_keys == 0, "tracker reset should clear indexes")

print("obsidian embeds workspace smoke test passed")
