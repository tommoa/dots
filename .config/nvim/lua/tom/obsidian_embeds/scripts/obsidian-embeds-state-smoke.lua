-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-state-smoke.lua

local test = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))
test.setup_runtime()

local state = require("tom.obsidian_embeds.state")

local bufnr = vim.api.nvim_create_buf(false, true)
local dependencies = state.new_dependency_set()
local buffer_state = state.new_buffer_state({
  bufnr = bufnr,
  workspace_root = "/tmp/vault",
  lines = { "![[Target]]" },
  cursor_row = 0,
  requirements = { needed = false },
})

test.assert_true(buffer_state.line_count == 1, "buffer state should record line count")
test.assert_true(type(buffer_state.rows) == "table", "buffer state should initialize rows")
test.assert_true(type(buffer_state.cache) == "table", "buffer state should initialize resolver cache")
test.assert_true(type(buffer_state.chunk_cache) == "table", "buffer state should initialize chunk cache")
test.assert_true(type(buffer_state.render_cache) == "table", "buffer state should initialize render cache")
test.assert_true(type(buffer_state.dependencies.paths) == "table", "buffer state should initialize dependencies")

local row_state = state.new_row_state({
  row = 0,
  refs = {},
  exact = false,
  virt_lines = {},
  dependencies = dependencies,
})
test.assert_true(type(row_state.conceal_marks) == "table", "row state should initialize conceal marks")
test.assert_true(row_state.render_mark == nil, "row state should start without a render mark")

local root_ctx = state.new_row_context(buffer_state, dependencies)
local child_ctx = state.child_context(root_ctx, { depth = 2 })
test.assert_true(child_ctx.depth == 2, "child context should apply overrides")
test.assert_true(child_ctx.stack == root_ctx.stack, "child context should share stack")
test.assert_true(child_ctx.cache == root_ctx.cache, "child context should share resolver cache")
test.assert_true(child_ctx.chunk_cache == root_ctx.chunk_cache, "child context should share chunk cache")
test.assert_true(child_ctx.render_cache == root_ctx.render_cache, "child context should share render cache")
test.assert_true(child_ctx.dependencies == root_ctx.dependencies, "child context should share dependencies")

local ok, err = pcall(state.new_row_state, { refs = {}, exact = false, virt_lines = {}, dependencies = dependencies })
test.assert_true(not ok and tostring(err):find("row", 1, true), "missing constructor fields should fail loudly")

print("obsidian embeds state smoke test passed")
