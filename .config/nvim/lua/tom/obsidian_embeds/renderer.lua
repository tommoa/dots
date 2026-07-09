local config = require("tom.obsidian_embeds.config")
local highlight = require("tom.obsidian_embeds.highlight")
local parser = require("tom.obsidian_embeds.parser")
local resolver = require("tom.obsidian_embeds.resolver")
local state = require("tom.obsidian_embeds.state")
local tracker = require("tom.obsidian_embeds.tracker")
local util = require("tom.obsidian_embeds.util")

local M = {}

---@return ObsidianEmbedsConfig
local function opts()
  return config.get()
end

---@param dst ObsidianEmbedsVirtLine[]
---@param lines? ObsidianEmbedsVirtLine[]
local function append_lines(dst, lines)
  if not lines then
    return
  end
  for _, line in ipairs(lines) do
    dst[#dst + 1] = line
  end
end

---@param text string
---@param hl_group? string
---@param depth integer
---@param chunk_cache table
---@return ObsidianEmbedsVirtLine
local function virt_line(text, hl_group, depth, chunk_cache)
  return highlight.virt_line(text, hl_group, depth, chunk_cache, opts())
end

---@param message string
---@param depth integer
---@return ObsidianEmbedsVirtLine
local function warn_line(message, depth)
  return highlight.warn_line(message, depth, opts())
end

---Render note lines recursively. A line that is exactly one embed is replaced by
---that embed's rendered lines; inline embeds keep the source line and append
---their rendered content below it.
---@param api ObsidianEmbedsApi
---@param lines string[]
---@param ctx ObsidianEmbedsRenderContext
---@return ObsidianEmbedsVirtLine[]
local function render_lines(api, lines, ctx)
  local out = {}

  for _, line in ipairs(lines) do
    local refs = parser.embed_refs(line)
    if parser.is_exact_embed_line(line, refs) and not resolver.should_ignore_ref(refs[1]) then
      append_lines(out, api.safe_render_ref(refs[1], state.child_context(ctx, {
        depth = ctx.depth + 1,
      })))
    else
      out[#out + 1] = virt_line(line, nil, ctx.depth, ctx.chunk_cache)
      for _, ref in ipairs(refs) do
        append_lines(out, api.safe_render_ref(ref, state.child_context(ctx, {
          depth = ctx.depth + 1,
        })))
      end
    end
  end

  return out
end

---@param api ObsidianEmbedsApi
---@param ref ObsidianEmbedsRef
---@param ctx ObsidianEmbedsRenderContext
---@return ObsidianEmbedsVirtLine[]?
function M.render_ref(api, ref, ctx)
  ctx = state.new_render_context(ctx)

  if resolver.should_ignore_ref(ref) then
    return nil
  end

  if ctx.depth > opts().max_depth then
    return { warn_line("Embed skipped: recursion limit reached", ctx.depth) }
  end

  -- Cache only top-level refs. Nested renders depend on the active recursion
  -- stack, while top-level cache entries can carry their dependency set safely.
  local can_use_render_cache = next(ctx.stack) == nil
  local render_dependencies
  if can_use_render_cache then
    render_dependencies = state.new_dependency_set()
    ctx.render_dependencies = render_dependencies
  end

  local notes, err = resolver.resolve_notes(ref, ctx)
  if err then
    return { warn_line("Embed error: " .. err, ctx.depth) }
  elseif #notes == 0 then
    return { warn_line("Embed not found: " .. ref.target, ctx.depth) }
  end

  local note = notes[1]
  tracker.track_dependency(ctx, note)
  local key = resolver.note_key(note, ref)
  -- The stack catches cycles between notes/anchors/blocks even when the maximum
  -- depth has not been reached yet.
  if ctx.stack[key] then
    return { warn_line("Embed skipped: recursion limit reached", ctx.depth) }
  end

  local render_cache_key
  if can_use_render_cache then
    render_cache_key = table.concat({
      key,
      ref.target or "",
      ref.label or "",
      tostring(ctx.depth),
      tostring(#notes),
      util.note_signature(note),
      opts().include_frontmatter and "frontmatter" or "no-frontmatter",
      opts().trim and "trim" or "no-trim",
      opts().hl_group,
      opts().warning_hl_group,
      opts().nested_marker or "",
      tostring(opts().max_depth),
    }, "\0")
    local cached = ctx.render_cache[render_cache_key]
    if cached then
      tracker.merge_dependency_set(ctx.dependencies, cached.dependencies)
      return cached.lines
    end
  end

  local lines, line_err = resolver.lines_for_ref(note, ref)
  if not lines then
    return { warn_line(line_err or ("Embed not found: " .. ref.target), ctx.depth) }
  end

  local out = {}
  if #notes > 1 then
    out[#out + 1] = warn_line("Multiple matches for: " .. ref.target, ctx.depth)
  end

  ctx.stack[key] = true
  local ok, rendered_or_err = pcall(render_lines, api, lines, state.for_note_context(ctx, note))
  ctx.stack[key] = nil
  if not ok then
    error(rendered_or_err, 0)
  end
  append_lines(out, rendered_or_err)

  if render_cache_key then
    ctx.render_cache[render_cache_key] = {
      lines = out,
      dependencies = tracker.copy_dependency_set(render_dependencies),
    }
  end
  return out
end

---@param api ObsidianEmbedsApi
---@param ref ObsidianEmbedsRef
---@param ctx ObsidianEmbedsRenderContext
---@return ObsidianEmbedsVirtLine[]?
function M.safe_render_ref(api, ref, ctx)
  local ok, lines_or_err = pcall(api.render_ref, ref, ctx)
  if ok then
    return lines_or_err
  end

  local depth = ctx and ctx.depth or 1
  return { warn_line("Embed error: " .. tostring(lines_or_err), depth) }
end

---@param api ObsidianEmbedsApi
---@param buffer_state ObsidianEmbedsBufferState
---@param row integer
---@param line string
---@return ObsidianEmbedsRowState?
function M.render_row_state(api, buffer_state, row, line)
  local virt_lines = {}
  local refs = parser.embed_refs(line)
  local rendered_refs = {}
  local dependencies = state.new_dependency_set()
  local ctx = state.new_row_context(buffer_state, dependencies)

  for _, ref in ipairs(refs) do
    append_lines(virt_lines, api.safe_render_ref(ref, ctx))
    if not resolver.should_ignore_ref(ref) then
      rendered_refs[#rendered_refs + 1] = ref
    end
  end

  if #virt_lines == 0 and #rendered_refs == 0 then
    return nil
  end

  return state.new_row_state({
    row = row,
    refs = rendered_refs,
    exact = parser.is_exact_embed_line(line, refs),
    virt_lines = virt_lines,
    dependencies = dependencies,
  })
end

return M
