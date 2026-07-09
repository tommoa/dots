-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-planner-smoke.lua

local test = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))
test.setup_runtime()

local planner = require("tom.obsidian_embeds.refresh_planner")

-- Scenario: planner decisions are conservative around line movement and
-- same-note embed structure, but allow local same-line rerenders.
local function base_state()
  return {
    source_lines = {
      "Plain",
      "![[Target]]",
      "## Heading",
      "Block text ^id",
    },
    has_same_note_refs = false,
    same_note_ranges = {},
    current_note = nil,
    current_note_opts = nil,
  }
end

local merged = planner.merge_changes({
  { first_row = 2, last_row = 2, line_count_changed = false },
  { first_row = 0, last_row = 0, line_count_changed = true },
})
test.assert_true(merged.first_row == 0 and merged.last_row == 2, "merge should coalesce row range")
test.assert_true(merged.line_count_changed == true, "merge should preserve line count changes")

local plan = planner.plan(base_state(), { "Plain changed", "![[Target]]", "## Heading", "Block text ^id" }, nil)
test.assert_true(plan.kind == "noop", "nil change should be noop")

plan = planner.plan(base_state(), { "Plain changed", "![[Target]]", "## Heading", "Block text ^id" }, {
  first_row = 0,
  last_row = 0,
  line_count_changed = false,
})
test.assert_true(plan.kind == "incremental", "plain same-count edit should be incremental")

plan = planner.plan(base_state(), { "Plain", "![[Other]]", "## Heading", "Block text ^id" }, {
  first_row = 1,
  last_row = 1,
  line_count_changed = false,
})
test.assert_true(plan.kind == "incremental", "non-local embed edit should be incremental")

plan = planner.plan(base_state(), { "Plain", "![[Target]]", "## Heading", "Block text ^id" }, {
  first_row = 0,
  last_row = 0,
  line_count_changed = true,
})
test.assert_true(plan.kind == "full" and plan.reason == "line_count_changed", "line count changes should be full refresh")

local same_note_state = base_state()
same_note_state.has_same_note_refs = true
same_note_state.same_note_ranges = { { start_row = 3, end_row = 3 } }
plan = planner.plan(same_note_state, { "Plain", "![[Target]]", "## Heading changed", "Block text ^id" }, {
  first_row = 2,
  last_row = 2,
  line_count_changed = false,
})
test.assert_true(plan.kind == "full" and plan.reason == "same_note_dependency", "heading edits with same-note refs should be full refresh")

plan = planner.plan(same_note_state, { "Plain", "![[Target]]", "## Heading", "Block changed ^id" }, {
  first_row = 3,
  last_row = 3,
  line_count_changed = false,
})
test.assert_true(plan.kind == "full" and plan.reason == "same_note_dependency", "same-note range edits should be full refresh")

print("obsidian embeds planner smoke test passed")
