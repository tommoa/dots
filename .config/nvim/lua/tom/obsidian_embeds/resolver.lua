local config = require("tom.obsidian_embeds.config")
local parser = require("tom.obsidian_embeds.parser")
local tracker = require("tom.obsidian_embeds.tracker")
local util = require("tom.obsidian_embeds.util")

local M = {}

---@return ObsidianEmbedsConfig
local function opts()
  return config.get()
end

---@param ref ObsidianEmbedsRef
---@return ObsidianEmbedsNoteOpts
local function ref_note_opts(ref)
  return {
    collect_sections = ref.anchor ~= nil,
    collect_anchor_links = ref.anchor ~= nil,
    collect_blocks = ref.block ~= nil,
    max_lines = math.huge,
  }
end

---@param note_opts ObsidianEmbedsNoteOpts
---@return string
local function note_opts_key(note_opts)
  return table.concat({
    note_opts.collect_sections and "S" or "-",
    note_opts.collect_anchor_links and "A" or "-",
    note_opts.collect_blocks and "B" or "-",
    tostring(note_opts.max_lines or ""),
  }, "")
end

---@param ref ObsidianEmbedsRef
---@return boolean
local function should_ignore_ref(ref)
  local attachment = require("obsidian.attachment")
  local obsidian_util = require("obsidian.util")
  local target = util.decode_target(ref.target)
  return obsidian_util.is_uri(target) or attachment.is_attachment_path(target)
end

---@param path string
---@param note_opts ObsidianEmbedsNoteOpts
---@return ObsidianEmbedsNote?
local function note_from_path(path, note_opts)
  local loaded_buf = util.loaded_buf_for_path(path)
  if loaded_buf then
    return require("obsidian.note").from_buffer(loaded_buf, note_opts)
  end
  return require("obsidian.note").from_file(path, note_opts)
end

---@param note ObsidianEmbedsNote
---@param note_opts ObsidianEmbedsNoteOpts
---@return ObsidianEmbedsNote
local function prefer_loaded_note(note, note_opts)
  local path = util.note_path_key(note)
  if not path then
    return note
  end
  return note_from_path(path, note_opts) or note
end

---@param target string
---@param note_opts ObsidianEmbedsNoteOpts
---@return ObsidianEmbedsNote[]
local function resolve_notes_from_obsidian(target, note_opts)
  local notes = require("obsidian.search").resolve_note(util.decode_target(target), {
    timeout = 1000,
    notes = note_opts,
  }) or {}

  for idx, note in ipairs(notes) do
    notes[idx] = prefer_loaded_note(note, note_opts)
  end
  return notes
end

---Resolve explicit relative refs from the note currently being rendered, not
---from the outer buffer. This matters for nested embeds that contain ./ links.
---@param target string
---@param ctx? ObsidianEmbedsRenderContext
---@return string?
local function relative_target_path(target, ctx)
  if not (ctx and ctx.base_dir) then
    return nil
  end

  if not (vim.startswith(target, "./") or vim.startswith(target, "../")) then
    return nil
  end

  local path = vim.fs.normalize(vim.fs.joinpath(ctx.base_dir, target))
  if not (vim.endswith(path, ".md") or vim.endswith(path, ".qmd") or vim.endswith(path, ".base")) then
    path = path .. ".md"
  end
  return path
end

---@param ctx? ObsidianEmbedsRenderContext
---@param target string
---@param notes ObsidianEmbedsNote[]
local function track_resolved_notes(ctx, target, notes)
  if not (ctx and ctx.dependencies) then
    return
  end

  if #notes == 0 then
    tracker.track_unresolved(ctx, target)
    return
  end

  for _, note in ipairs(notes) do
    tracker.track_dependency(ctx, note)
  end
end

---@param ref ObsidianEmbedsRef
---@return boolean
function M.should_ignore_ref(ref)
  return should_ignore_ref(ref)
end

---@param note ObsidianEmbedsNote
---@param ref ObsidianEmbedsRef
---@return string
function M.note_key(note, ref)
  local path = note.path and tostring(note.path) or ref.target
  return table.concat({ path, ref.anchor or "", ref.block or "" }, "#")
end

---Resolve a ref to candidate notes and record either path or unresolved-name
---dependencies. An empty target is a same-note embed and depends on current_note.
---Missing relative refs are tracked by their normalized candidate path so a
---later BufWritePost can refresh them through path_reference_keys().
---@param ref ObsidianEmbedsRef
---@param ctx? ObsidianEmbedsRenderContext
---@return ObsidianEmbedsNote[] notes
---@return string? err
function M.resolve_notes(ref, ctx)
  local target = util.decode_target(ref.target)
  if target == "" then
    if ctx and ctx.current_note then
      tracker.track_dependency(ctx, ctx.current_note)
      return { ctx.current_note }
    elseif ctx and ctx.current_note_error then
      return {}, ctx.current_note_error
    end
  end

  local note_opts = ref_note_opts(ref)
  local relative_path = relative_target_path(target, ctx)
  local resolve_target = relative_path or target
  local cache_key = resolve_target .. "\0" .. note_opts_key(note_opts)
  if ctx and ctx.cache and ctx.cache[cache_key] then
    local notes = ctx.cache[cache_key]
    track_resolved_notes(ctx, relative_path or target, notes)
    return notes
  end

  local notes
  if relative_path then
    local loaded = util.loaded_buf_for_path(relative_path) or vim.uv.fs_stat(relative_path)
    loaded = loaded and note_from_path(relative_path, note_opts)
    notes = loaded and { loaded } or {}
  else
    notes = resolve_notes_from_obsidian(target, note_opts)
  end
  track_resolved_notes(ctx, relative_path or target, notes)
  if ctx and ctx.cache then
    ctx.cache[cache_key] = notes
  end
  return notes
end

---@param lines string[]
---@param start_row integer Zero-based, inclusive.
---@param end_row integer Zero-based, exclusive.
---@return string[]
local function slice_lines(lines, start_row, end_row)
  local out = {}
  local start_idx = math.max(start_row + 1, 1)
  local end_idx = math.min(end_row, #lines)
  for idx = start_idx, end_idx do
    out[#out + 1] = lines[idx]
  end
  return out
end

---@param note ObsidianEmbedsNote
---@return string[]
local function without_frontmatter(note)
  if opts().include_frontmatter then
    return slice_lines(note.contents, 0, #note.contents)
  end
  local start_row = note.frontmatter_end_line or 0
  return slice_lines(note.contents, start_row, #note.contents)
end

---@param line string
---@param block_id? string
---@return string
local function strip_block_id(line, block_id)
  if not block_id then
    return line
  end
  return line:gsub("%s+" .. vim.pesc(block_id) .. "%s*$", "")
end

---Return the exact note lines an embed should display: block, heading section,
---or whole note. Heading aliases are applied after slicing.
---@param note ObsidianEmbedsNote
---@param ref ObsidianEmbedsRef
---@return string[]? lines
---@return string? err
function M.lines_for_ref(note, ref)
  if ref.block then
    local block = note:resolve_block(ref.block)
    if not block then
      return nil, "Block not found: " .. ref.block
    end

    local lines
    if block.section and block.section.range then
      local range = block.section.range
      lines = slice_lines(note.contents, range.start_row, range.end_row)
    elseif block.line then
      lines = { note.contents[block.line] or "" }
    else
      lines = { block.block or "" }
    end

    for idx, line in ipairs(lines) do
      lines[idx] = strip_block_id(line, block.id)
    end
    return parser.finalize_lines(lines, opts())
  end

  if ref.anchor then
    local anchor_link = ref.anchor
    if not vim.startswith(anchor_link, "#") then
      anchor_link = "#" .. anchor_link
    end

    local anchor = note:resolve_anchor_link(anchor_link)
    if anchor and anchor.section and anchor.section.range then
      local range = anchor.section.range
      local lines = slice_lines(note.contents, range.start_row, range.end_row)
      return parser.finalize_heading_lines(lines, ref, opts())
    end

    return nil, "Heading not found: " .. ref.anchor
  end

  return parser.finalize_heading_lines(without_frontmatter(note), ref, opts())
end

---@param requirements ObsidianEmbedsCurrentNoteRequirements
---@param ref ObsidianEmbedsRef
function M.add_current_note_requirements(requirements, ref)
  if util.decode_target(ref.target) ~= "" or should_ignore_ref(ref) then
    return
  end

  requirements.needed = true
  requirements.collect_anchor_links = requirements.collect_anchor_links or ref.anchor ~= nil
  requirements.collect_sections = requirements.collect_sections or ref.anchor ~= nil
  requirements.collect_blocks = requirements.collect_blocks or ref.block ~= nil
end

---@return ObsidianEmbedsCurrentNoteRequirements
function M.empty_requirements()
  return {
    needed = false,
    collect_sections = false,
    collect_anchor_links = false,
    collect_blocks = false,
  }
end

---@param lines string[]
---@return ObsidianEmbedsCurrentNoteRequirements
function M.scan_current_note_requirements(lines)
  local requirements = M.empty_requirements()

  for _, line in ipairs(lines) do
    for _, ref in ipairs(parser.embed_refs(line)) do
      M.add_current_note_requirements(requirements, ref)
    end
  end

  return requirements
end

---@param requirements ObsidianEmbedsCurrentNoteRequirements
---@return ObsidianEmbedsNoteOpts?
function M.current_note_opts(requirements)
  if not requirements.needed then
    return nil
  end

  return {
    collect_sections = requirements.collect_sections,
    collect_anchor_links = requirements.collect_anchor_links,
    collect_blocks = requirements.collect_blocks,
    max_lines = math.huge,
  }
end

---@param state ObsidianEmbedsBufferState
---@param requirements ObsidianEmbedsCurrentNoteRequirements
---@return boolean
function M.current_note_requirements_satisfied(state, requirements)
  if not requirements.needed then
    return true
  elseif not state.current_note or not state.current_note_opts then
    return false
  end

  return (not requirements.collect_sections or state.current_note_opts.collect_sections)
    and (not requirements.collect_anchor_links or state.current_note_opts.collect_anchor_links)
    and (not requirements.collect_blocks or state.current_note_opts.collect_blocks)
end

---@param note? ObsidianEmbedsNote
---@param ref ObsidianEmbedsRef
---@return ObsidianEmbedsSameNoteRange?
local function same_note_range_for_ref(note, ref)
  if not note or util.decode_target(ref.target) ~= "" then
    return nil
  end

  if ref.block then
    local block = note:resolve_block(ref.block)
    if not block then
      return nil
    elseif block.section and block.section.range then
      return {
        start_row = block.section.range.start_row,
        end_row = block.section.range.end_row - 1,
      }
    elseif block.line then
      return {
        start_row = block.line - 1,
        end_row = block.line - 1,
      }
    end
  elseif ref.anchor then
    local anchor_link = ref.anchor
    if not vim.startswith(anchor_link, "#") then
      anchor_link = "#" .. anchor_link
    end

    local anchor = note:resolve_anchor_link(anchor_link)
    if anchor and anchor.section and anchor.section.range then
      return {
        start_row = anchor.section.range.start_row,
        end_row = anchor.section.range.end_row - 1,
      }
    end
  else
    return {
      start_row = 0,
      end_row = math.max(#note.contents - 1, 0),
    }
  end

  return nil
end

---@param state ObsidianEmbedsBufferState
function M.refresh_same_note_ranges(state)
  local ranges = {}
  if state.current_note then
    for _, row_state in pairs(state.rows) do
      for _, ref in ipairs(row_state.refs or {}) do
        local range = same_note_range_for_ref(state.current_note, ref)
        if range then
          ranges[#ranges + 1] = range
        end
      end
    end
  end
  state.same_note_ranges = ranges
end

---@param old_refs ObsidianEmbedsRef[]
---@param new_refs ObsidianEmbedsRef[]
---@return ObsidianEmbedsCurrentNoteRequirements
function M.row_refs_requirements(old_refs, new_refs)
  local requirements = M.empty_requirements()

  for _, ref in ipairs(old_refs or {}) do
    M.add_current_note_requirements(requirements, ref)
  end
  for _, ref in ipairs(new_refs or {}) do
    M.add_current_note_requirements(requirements, ref)
  end

  return requirements
end

---@param refs ObsidianEmbedsRef[]
---@return boolean
function M.refs_include_same_note(refs)
  for _, ref in ipairs(refs or {}) do
    if util.decode_target(ref.target) == "" and not should_ignore_ref(ref) then
      return true
    end
  end
  return false
end

---@param line string
---@return boolean
local function line_may_affect_note_structure(line)
  return line:match("^%s*#+%s+") ~= nil or line:match("%s%^%S+") ~= nil
end

---@param state ObsidianEmbedsBufferState
---@param row integer
---@return boolean
local function row_overlaps_same_note_range(state, row)
  for _, range in ipairs(state.same_note_ranges or {}) do
    if range.start_row <= row and row <= range.end_row then
      return true
    end
  end
  return false
end

---Same-note embeds can depend on later lines in the same buffer. Prefer a full
---refresh when edits could alter the current note's headings, blocks, or any
---already-rendered same-note range.
---@param state ObsidianEmbedsBufferState
---@param row integer
---@param old_line string
---@param new_line string
---@param old_refs ObsidianEmbedsRef[]
---@param new_refs ObsidianEmbedsRef[]
---@return boolean
function M.should_full_refresh_for_same_note_change(state, row, old_line, new_line, old_refs, new_refs)
  if not state.has_same_note_refs then
    return false
  end

  if M.refs_include_same_note(old_refs) or M.refs_include_same_note(new_refs) then
    return true
  elseif #old_refs > 0 or #new_refs > 0 then
    return false
  end

  return row_overlaps_same_note_range(state, row)
    or line_may_affect_note_structure(old_line)
    or line_may_affect_note_structure(new_line)
end

return M
