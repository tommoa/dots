-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-performance-smoke.lua

local test = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))
test.setup_runtime()

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.mkdir(root .. "/.obsidian", "p")

local target = { "# Target", "Repeated **bold** [link](Target.md) `code`" }
for _ = 1, 30 do
  target[#target + 1] = "Repeated **bold** [link](Target.md) `code`"
end
test.write_file(root .. "/Target.md", target)

local main = {}
for _ = 1, 50 do
  main[#main + 1] = "![[Target]]"
end
main[#main + 1] = "plain edit row"
test.write_file(root .. "/Main.md", main)

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    {
      name = "performance-smoke",
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

vim.treesitter.get_string_parser("# sample", "markdown")
vim.treesitter.get_string_parser("**sample**", "markdown_inline")
assert(vim.treesitter.query.get("markdown", "highlights"), "missing markdown highlight query")
assert(vim.treesitter.query.get("markdown_inline", "highlights"), "missing markdown_inline highlight query")

local embeds = require("tom.obsidian_embeds")
embeds.setup({ debounce_ms = 10 })

vim.cmd.edit(root .. "/Main.md")
local bufnr = vim.api.nvim_get_current_buf()
vim.b[bufnr].obsidian_buffer = true
embeds.attach(bufnr)
embeds.refresh(bufnr)

-- Scenario: repeated rendered lines hit the highlight cache, and plain
-- incremental edits do not invoke note rendering.
local stats = embeds.stats(bufnr)
test.assert_true(stats.highlight.hits > stats.highlight.misses, "repeated rendered lines should hit highlight cache")
test.assert_true(stats.highlight.markdown_parses == stats.highlight.markdown_inline_parses, "markdown and inline parse counts should match")

local render_ref = embeds.render_ref
local render_ref_calls = 0
embeds.render_ref = function(...)
  render_ref_calls = render_ref_calls + 1
  return render_ref(...)
end
vim.api.nvim_buf_set_lines(bufnr, #main - 1, #main, false, { "plain edit row changed" })
embeds.refresh_changed(bufnr)
embeds.render_ref = render_ref
test.assert_true(render_ref_calls == 0, "plain incremental edit should not call render_ref")
test.assert_true(embeds.stats(bufnr).last_plan_kind == "incremental", "plain edit should use incremental refresh")

print("obsidian embeds performance smoke test passed")
