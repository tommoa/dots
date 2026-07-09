local parser = require("tom.obsidian_embeds.parser")
local resolver = require("tom.obsidian_embeds.resolver")

local M = {}

---@class ObsidianEmbedsRefreshChange
---@field first_row integer
---@field last_row integer
---@field line_count_changed boolean

---@class ObsidianEmbedsRowChange
---@field row integer
---@field old_line string
---@field new_line string
---@field old_refs ObsidianEmbedsRef[]
---@field new_refs ObsidianEmbedsRef[]

---@class ObsidianEmbedsRefreshPlan
---@field kind "noop"|"full"|"incremental"
---@field reason? "line_count_changed"|"large_change"|"same_note_dependency"|"current_note_requirements"
---@field first_row? integer
---@field last_row? integer
---@field row_changes? ObsidianEmbedsRowChange[]
---@field changed_requirements? ObsidianEmbedsCurrentNoteRequirements

local max_incremental_rows = 20

---@param changes? ObsidianEmbedsRefreshChange[]
---@return ObsidianEmbedsRefreshChange?
function M.merge_changes(changes)
  if not changes or #changes == 0 then
    return nil
  end

  local first_row = math.huge
  local last_row = -1
  local line_count_changed = false
  for _, change in ipairs(changes) do
    line_count_changed = line_count_changed or change.line_count_changed
    first_row = math.min(first_row, change.first_row)
    last_row = math.max(last_row, change.last_row)
  end

  if first_row == math.huge then
    return nil
  elseif last_row < first_row then
    last_row = first_row
  end

  return {
    first_row = first_row,
    last_row = last_row,
    line_count_changed = line_count_changed,
  }
end

---Plan the cheapest safe refresh. Any edit that shifts line numbers or can alter
---same-note embed structure falls back to a full refresh.
---@param state ObsidianEmbedsBufferState
---@param lines string[]
---@param change? ObsidianEmbedsRefreshChange
---@return ObsidianEmbedsRefreshPlan
function M.plan(state, lines, change)
  if not change then
    return { kind = "noop" }
  end

  if change.line_count_changed then
    return { kind = "full", reason = "line_count_changed" }
  end

  if (change.last_row - change.first_row) > max_incremental_rows then
    return { kind = "full", reason = "large_change" }
  end

  local changed_requirements = resolver.empty_requirements()
  local row_changes = {}

  for row = change.first_row, change.last_row do
    local old_line = state.source_lines[row + 1] or ""
    local new_line = lines[row + 1] or ""
    local old_refs = parser.embed_refs(old_line)
    local new_refs = parser.embed_refs(new_line)

    if resolver.should_full_refresh_for_same_note_change(state, row, old_line, new_line, old_refs, new_refs) then
      return { kind = "full", reason = "same_note_dependency" }
    end

    local row_requirements = resolver.row_refs_requirements(old_refs, new_refs)
    changed_requirements.needed = changed_requirements.needed or row_requirements.needed
    changed_requirements.collect_sections = changed_requirements.collect_sections or row_requirements.collect_sections
    changed_requirements.collect_anchor_links = changed_requirements.collect_anchor_links or row_requirements.collect_anchor_links
    changed_requirements.collect_blocks = changed_requirements.collect_blocks or row_requirements.collect_blocks

    if not resolver.current_note_requirements_satisfied(state, changed_requirements) then
      return { kind = "full", reason = "current_note_requirements" }
    end

    row_changes[#row_changes + 1] = {
      row = row,
      old_line = old_line,
      new_line = new_line,
      old_refs = old_refs,
      new_refs = new_refs,
    }
  end

  return {
    kind = "incremental",
    first_row = change.first_row,
    last_row = change.last_row,
    row_changes = row_changes,
    changed_requirements = changed_requirements,
  }
end

return M
