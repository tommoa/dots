local config = require("tom.obsidian_embeds.config")

local M = {}

---@alias ObsidianEmbedsPathIndex table<string, table<string, true>>
---@alias ObsidianEmbedsVirtChunk [string, string]
---@alias ObsidianEmbedsVirtLine ObsidianEmbedsVirtChunk[]
---@alias ObsidianEmbedsRefRange { start_col: integer, end_col: integer }

---@class ObsidianEmbedsRef
---@field raw string
---@field target string
---@field embed boolean
---@field kind? string
---@field label? string
---@field anchor? string
---@field block? string
---@field range ObsidianEmbedsRefRange

---@class ObsidianEmbedsSectionRange
---@field start_row integer
---@field end_row integer

---@class ObsidianEmbedsSection
---@field range ObsidianEmbedsSectionRange

---@class ObsidianEmbedsBlock
---@field id? string
---@field block? string
---@field line? integer
---@field section? ObsidianEmbedsSection

---@class ObsidianEmbedsNote
---@field id? string
---@field title? string
---@field path? string
---@field bufnr? integer
---@field contents string[]
---@field aliases? string[]
---@field frontmatter_end_line? integer
---@field display_name? fun(self: ObsidianEmbedsNote): string
---@field reference_ids? fun(self: ObsidianEmbedsNote, opts?: table): string[]
---@field get_reference_paths? fun(self: ObsidianEmbedsNote, opts?: table): string[]
---@field resolve_block fun(self: ObsidianEmbedsNote, block: string): ObsidianEmbedsBlock?
---@field resolve_anchor_link fun(self: ObsidianEmbedsNote, anchor: string): { section?: ObsidianEmbedsSection }?

---@class ObsidianEmbedsNoteOpts
---@field collect_sections? boolean
---@field collect_anchor_links? boolean
---@field collect_blocks? boolean
---@field max_lines? integer

---@class ObsidianEmbedsCurrentNoteRequirements
---@field needed boolean
---@field collect_sections boolean
---@field collect_anchor_links boolean
---@field collect_blocks boolean

---@class ObsidianEmbedsDependencySet
---@field paths ObsidianEmbedsPathIndex Workspace root to absolute note paths.
---@field unresolved ObsidianEmbedsPathIndex Workspace root to unresolved reference keys.

---@class ObsidianEmbedsRowState
---@field row integer
---@field refs ObsidianEmbedsRef[]
---@field exact boolean True when the source line is exactly one embed ref.
---@field virt_lines ObsidianEmbedsVirtLine[]
---@field conceal_marks integer[]
---@field render_mark? integer
---@field dependencies ObsidianEmbedsDependencySet

---@class ObsidianEmbedsSameNoteRange
---@field start_row integer
---@field end_row integer

---@class ObsidianEmbedsHighlightStats
---@field hits integer
---@field misses integer
---@field markdown_parses integer
---@field markdown_inline_parses integer
---@field cached_lines integer

---@class ObsidianEmbedsStats
---@field elapsed_ms? number
---@field rendered_rows? integer
---@field rendered_lines? integer
---@field path_keys? integer
---@field unresolved_keys? integer
---@field workspaces? integer
---@field indexed_buffers? integer
---@field last_plan_kind? string
---@field last_plan_reason? string
---@field changed_rows? integer
---@field highlight? ObsidianEmbedsHighlightStats

---@class ObsidianEmbedsBufferState
---@field bufnr integer
---@field workspace_root string
---@field base_dir? string
---@field cursor_row? integer
---@field line_count integer
---@field source_lines string[]
---@field changedtick integer
---@field option_generation integer
---@field rows table<integer, ObsidianEmbedsRowState>
---@field cache table<string, ObsidianEmbedsNote[]>
---@field chunk_cache table
---@field render_cache table<string, { lines: ObsidianEmbedsVirtLine[], dependencies: ObsidianEmbedsDependencySet }>
---@field dependencies ObsidianEmbedsDependencySet
---@field same_note_ranges ObsidianEmbedsSameNoteRange[]
---@field current_note_opts? ObsidianEmbedsNoteOpts
---@field current_note? ObsidianEmbedsNote
---@field current_note_error? string
---@field has_same_note_refs boolean

---@class ObsidianEmbedsRenderContext
---@field depth integer
---@field stack table<string, true>
---@field workspace_root string
---@field base_dir? string Directory relative links resolve from for the note currently being rendered.
---@field current_note? ObsidianEmbedsNote
---@field current_note_error? string
---@field cache table<string, ObsidianEmbedsNote[]>
---@field chunk_cache table
---@field render_cache table<string, { lines: ObsidianEmbedsVirtLine[], dependencies: ObsidianEmbedsDependencySet }>
---@field dependencies ObsidianEmbedsDependencySet
---@field render_dependencies? ObsidianEmbedsDependencySet

---@class ObsidianEmbedsApi
---@field render_ref fun(ref: ObsidianEmbedsRef, ctx: ObsidianEmbedsRenderContext): ObsidianEmbedsVirtLine[]?
---@field safe_render_ref fun(ref: ObsidianEmbedsRef, ctx: ObsidianEmbedsRenderContext): ObsidianEmbedsVirtLine[]?
---@field refresh fun(bufnr?: integer)
---@field refresh_changed fun(bufnr?: integer)
---@field update_cursor fun(bufnr?: integer)
---@field stats fun(bufnr?: integer): ObsidianEmbedsStats
---@field toggle fun(bufnr?: integer)
---@field attach fun(bufnr?: integer)
---@field setup? fun(user_opts?: table)
---@field namespace? string

local function assert_present(value, name)
  assert(value ~= nil, "tom.obsidian_embeds state requires " .. name)
  return value
end

---@return ObsidianEmbedsDependencySet
function M.new_dependency_set()
  return {
    paths = {},
    unresolved = {},
  }
end

---@param args { bufnr: integer, workspace_root: string, base_dir?: string, cursor_row?: integer, lines: string[], requirements: ObsidianEmbedsCurrentNoteRequirements, current_note_opts?: ObsidianEmbedsNoteOpts, current_note?: ObsidianEmbedsNote, current_note_error?: string }
---@return ObsidianEmbedsBufferState
function M.new_buffer_state(args)
  args = args or {}
  local lines = assert_present(args.lines, "lines")
  local requirements = assert_present(args.requirements, "requirements")
  local bufnr = assert_present(args.bufnr, "bufnr")

  return {
    bufnr = bufnr,
    workspace_root = assert_present(args.workspace_root, "workspace_root"),
    base_dir = args.base_dir,
    cursor_row = args.cursor_row,
    line_count = #lines,
    source_lines = lines,
    changedtick = vim.b[bufnr].changedtick or 0,
    option_generation = config.generation(),
    rows = {},
    cache = {},
    chunk_cache = {},
    render_cache = {},
    dependencies = M.new_dependency_set(),
    same_note_ranges = {},
    current_note_opts = args.current_note_opts,
    current_note = args.current_note,
    current_note_error = args.current_note_error,
    has_same_note_refs = requirements.needed == true,
  }
end

---@param args { row: integer, refs: ObsidianEmbedsRef[], exact: boolean, virt_lines: ObsidianEmbedsVirtLine[], dependencies: ObsidianEmbedsDependencySet }
---@return ObsidianEmbedsRowState
function M.new_row_state(args)
  args = args or {}
  return {
    row = assert_present(args.row, "row"),
    refs = assert_present(args.refs, "refs"),
    exact = assert_present(args.exact, "exact"),
    virt_lines = assert_present(args.virt_lines, "virt_lines"),
    conceal_marks = {},
    render_mark = nil,
    dependencies = assert_present(args.dependencies, "dependencies"),
  }
end

---@param args ObsidianEmbedsRenderContext
---@return ObsidianEmbedsRenderContext
function M.new_render_context(args)
  args = args or {}
  return {
    depth = assert_present(args.depth, "depth"),
    stack = assert_present(args.stack, "stack"),
    workspace_root = assert_present(args.workspace_root, "workspace_root"),
    base_dir = args.base_dir,
    current_note = args.current_note,
    current_note_error = args.current_note_error,
    cache = assert_present(args.cache, "cache"),
    chunk_cache = assert_present(args.chunk_cache, "chunk_cache"),
    render_cache = assert_present(args.render_cache, "render_cache"),
    dependencies = assert_present(args.dependencies, "dependencies"),
    render_dependencies = args.render_dependencies,
  }
end

---@param buffer_state ObsidianEmbedsBufferState
---@param dependencies ObsidianEmbedsDependencySet
---@return ObsidianEmbedsRenderContext
function M.new_row_context(buffer_state, dependencies)
  return M.new_render_context({
    depth = 1,
    stack = {},
    workspace_root = buffer_state.workspace_root,
    base_dir = buffer_state.base_dir,
    current_note = buffer_state.current_note,
    current_note_error = buffer_state.current_note_error,
    cache = buffer_state.cache,
    chunk_cache = buffer_state.chunk_cache,
    render_cache = buffer_state.render_cache,
    dependencies = dependencies,
  })
end

---@param ctx ObsidianEmbedsRenderContext
---@param overrides? table
---@return ObsidianEmbedsRenderContext
function M.child_context(ctx, overrides)
  overrides = overrides or {}
  return M.new_render_context({
    depth = overrides.depth or ctx.depth,
    stack = overrides.stack or ctx.stack,
    workspace_root = overrides.workspace_root or ctx.workspace_root,
    base_dir = overrides.base_dir ~= nil and overrides.base_dir or ctx.base_dir,
    current_note = overrides.current_note ~= nil and overrides.current_note or ctx.current_note,
    current_note_error = overrides.current_note_error ~= nil and overrides.current_note_error or ctx.current_note_error,
    cache = overrides.cache or ctx.cache,
    chunk_cache = overrides.chunk_cache or ctx.chunk_cache,
    render_cache = overrides.render_cache or ctx.render_cache,
    dependencies = overrides.dependencies or ctx.dependencies,
    render_dependencies = overrides.render_dependencies ~= nil and overrides.render_dependencies or ctx.render_dependencies,
  })
end

---@param ctx ObsidianEmbedsRenderContext
---@param note ObsidianEmbedsNote
---@return ObsidianEmbedsRenderContext
function M.for_note_context(ctx, note)
  return M.child_context(ctx, {
    current_note = note,
    current_note_error = ctx.current_note_error,
    base_dir = note and note.path and vim.fs.dirname(tostring(note.path)) or ctx.base_dir,
  })
end

return M
