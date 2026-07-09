local M = {}

---Extract renderable embed refs from one source line.
---Footnotes are parsed by obsidian.nvim as refs, but this renderer never treats
---them as note embeds.
---@param line string
---@return ObsidianEmbedsRef[]
function M.embed_refs(line)
  if not line:find("![", 1, true) then
    return {}
  end

  local parse_refs = require("obsidian.parse.refs")
  local refs = {}
  for _, ref in ipairs(parse_refs.extract(line)) do
    if ref.embed and ref.kind ~= "footnote" then
      refs[#refs + 1] = ref
    end
  end
  table.sort(refs, function(a, b)
    if a.range.start_col == b.range.start_col then
      return a.range.end_col < b.range.end_col
    end
    return a.range.start_col < b.range.start_col
  end)
  return refs
end

---@param line string
---@param ref ObsidianEmbedsRef
---@return string
function M.aliased_heading(line, ref)
  if not ref.label or ref.label == "" then
    return line
  end

  local markers, space = line:match("^(#+)(%s+)")
  if markers then
    return markers .. space .. ref.label
  end

  return line
end

---@param lines string[]
---@param opts ObsidianEmbedsConfig
---@return string[]
local function trim_boundary_lines(lines, opts)
  if not opts.trim then
    return lines
  end

  local first = 1
  while first <= #lines and vim.trim(lines[first]) == "" do
    first = first + 1
  end

  local last = #lines
  while last >= first and vim.trim(lines[last]) == "" do
    last = last - 1
  end

  local out = {}
  for idx = first, last do
    out[#out + 1] = lines[idx]
  end
  return out
end

---@param lines string[]
---@param opts ObsidianEmbedsConfig
---@return string[]
function M.finalize_lines(lines, opts)
  return trim_boundary_lines(lines, opts)
end

---Apply a ref alias only to the first rendered heading line, matching Obsidian's
---embed label behavior without mutating note contents.
---@param lines string[]
---@param ref ObsidianEmbedsRef
---@param opts ObsidianEmbedsConfig
---@return string[]
function M.finalize_heading_lines(lines, ref, opts)
  lines = trim_boundary_lines(lines, opts)
  if lines[1] then
    lines[1] = M.aliased_heading(lines[1], ref)
  end
  return lines
end

---@param line string
---@param refs ObsidianEmbedsRef[]
---@return boolean
function M.is_exact_embed_line(line, refs)
  return #refs == 1 and vim.trim(line) == refs[1].raw
end

return M
