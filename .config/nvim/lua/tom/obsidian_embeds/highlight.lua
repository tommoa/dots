local M = {}

---@class ObsidianEmbedsTreeSitterSpan
---@field start_col integer
---@field end_col integer
---@field hl_group string

---@type table<string, any>
local ts_queries = {}
local stats_key = {}

---@param cache? table
---@return ObsidianEmbedsHighlightStats?
local function ensure_stats(cache)
  if not cache then
    return nil
  end

  cache[stats_key] = cache[stats_key] or {
    hits = 0,
    misses = 0,
    markdown_parses = 0,
    markdown_inline_parses = 0,
    cached_lines = 0,
  }
  return cache[stats_key]
end

---@param depth? integer
---@return string
local function prefix_for_depth(depth)
  return string.rep("  ", math.max((depth or 1) - 1, 0))
end

---@param chunks ObsidianEmbedsVirtLine
---@param text string
---@param hl_group? string
---@param opts ObsidianEmbedsConfig
local function append_chunk(chunks, text, hl_group, opts)
  if text == "" then
    return
  end

  local last = chunks[#chunks]
  hl_group = hl_group or opts.hl_group
  if last and last[2] == hl_group then
    last[1] = last[1] .. text
  else
    chunks[#chunks + 1] = { text, hl_group }
  end
end

---@param chunks ObsidianEmbedsVirtLine
---@return ObsidianEmbedsVirtLine
local function clone_chunks(chunks)
  local out = {}
  for idx, chunk in ipairs(chunks) do
    out[idx] = { chunk[1], chunk[2] }
  end
  return out
end

---@param chunks ObsidianEmbedsVirtLine
---@param depth integer
---@param opts ObsidianEmbedsConfig
---@return ObsidianEmbedsVirtLine
local function with_prefix(chunks, depth, opts)
  local prefix = prefix_for_depth(depth)
  if prefix ~= "" then
    table.insert(chunks, 1, { prefix, opts.hl_group })
  end

  if (depth or 1) > 1 and opts.nested_marker and opts.nested_marker ~= "" then
    local marker_idx = prefix ~= "" and 2 or 1
    table.insert(chunks, marker_idx, { opts.nested_marker, "@markup.quote" })
  end

  return chunks
end

---@param capture_name string
---@return string?
local function capture_hl_group(capture_name)
  if capture_name == "spell" or capture_name == "nospell" or capture_name == "conceal" then
    return nil
  elseif vim.startswith(capture_name, "_") then
    return nil
  elseif vim.startswith(capture_name, "@") then
    return capture_name
  end

  return "@" .. capture_name
end

---@param hl_group string
---@return integer
local function capture_priority(hl_group)
  if hl_group == "@markup.link.url" then
    return 80
  elseif hl_group == "@markup.link.label" then
    return 75
  elseif hl_group == "@markup.raw" then
    return 70
  elseif hl_group == "@markup.strong" or hl_group == "@markup.italic" then
    return 65
  elseif vim.startswith(hl_group, "@markup.heading") then
    return 60
  elseif hl_group == "@markup.list" or hl_group == "@markup.quote" then
    return 55
  elseif vim.startswith(hl_group, "@punctuation") then
    return 45
  elseif hl_group == "@markup.link" then
    return 40
  else
    return 50
  end
end

---@param lang string
---@param text string
---@return ObsidianEmbedsTreeSitterSpan[]
local function collect_tree_sitter_spans(lang, text)
  local parser = vim.treesitter.get_string_parser(text, lang)
  ts_queries[lang] = ts_queries[lang] or assert(vim.treesitter.query.get(lang, "highlights"), "missing " .. lang .. " highlight query")
  local query = ts_queries[lang]
  local tree = assert(parser:parse()[1], "failed to parse " .. lang)
  local root = tree:root()
  local spans = {}

  for id, node in query:iter_captures(root, text, 0, 1) do
    local hl_group = capture_hl_group(query.captures[id])
    if hl_group then
      local start_row, start_col, end_row, end_col = node:range()
      if start_row == 0 then
        if end_row > 0 then
          end_col = #text
        end
        if start_col < end_col then
          spans[#spans + 1] = {
            start_col = start_col,
            end_col = end_col,
            hl_group = hl_group,
          }
        end
      end
    end
  end

  return spans
end

---@param text string
---@param cache? table
---@param opts ObsidianEmbedsConfig
---@return ObsidianEmbedsVirtLine
local function tree_sitter_chunks(text, cache, opts)
  if cache and cache[text] then
    local stats = ensure_stats(cache)
    stats.hits = stats.hits + 1
    return clone_chunks(cache[text])
  end

  local stats = ensure_stats(cache)
  if stats then
    stats.misses = stats.misses + 1
  end

  if text == "" then
    local chunks = { { "", opts.hl_group } }
    if cache then
      cache[text] = clone_chunks(chunks)
      stats.cached_lines = stats.cached_lines + 1
    end
    return chunks
  end

  if stats then
    stats.markdown_parses = stats.markdown_parses + 1
    stats.markdown_inline_parses = stats.markdown_inline_parses + 1
  end
  local spans = collect_tree_sitter_spans("markdown", text)
  vim.list_extend(spans, collect_tree_sitter_spans("markdown_inline", text))

  local chunks = {}
  local breakpoints = { [0] = true, [#text] = true }
  for _, span in ipairs(spans) do
    breakpoints[span.start_col] = true
    breakpoints[span.end_col] = true
  end

  local sorted_breakpoints = vim.tbl_keys(breakpoints)
  table.sort(sorted_breakpoints)

  for idx = 1, #sorted_breakpoints - 1 do
    local start_col = sorted_breakpoints[idx]
    local end_col = sorted_breakpoints[idx + 1]
    local hl_group = opts.hl_group
    local priority = 0

    -- Multiple captures can cover the same bytes. Keep one chunk boundary map
    -- and choose the highest-priority capture for each segment.
    for _, span in ipairs(spans) do
      if span.start_col <= start_col and end_col <= span.end_col then
        local span_priority = capture_priority(span.hl_group)
        if span_priority > priority then
          hl_group = span.hl_group
          priority = span_priority
        end
      end
    end

    append_chunk(chunks, text:sub(start_col + 1, end_col), hl_group, opts)
  end

  if #chunks == 0 then
    chunks[1] = { text, opts.hl_group }
  end
  if cache then
    cache[text] = clone_chunks(chunks)
    stats.cached_lines = stats.cached_lines + 1
  end
  return chunks
end

---@param text string
---@param hl_group? string
---@param depth integer
---@param chunk_cache? table
---@param opts ObsidianEmbedsConfig
---@return ObsidianEmbedsVirtLine
function M.virt_line(text, hl_group, depth, chunk_cache, opts)
  if hl_group then
    if text == "" then
      return { { text, hl_group } }
    end
    return with_prefix({ { text, hl_group } }, depth, opts)
  end
  return with_prefix(tree_sitter_chunks(text, chunk_cache, opts), depth, opts)
end

---@param message string
---@param depth integer
---@param opts ObsidianEmbedsConfig
---@return ObsidianEmbedsVirtLine
function M.warn_line(message, depth, opts)
  return M.virt_line(message, opts.warning_hl_group, depth, nil, opts)
end

---@param cache? table
---@return ObsidianEmbedsHighlightStats
function M.cache_stats(cache)
  local stats = cache and cache[stats_key] or nil
  return {
    hits = stats and stats.hits or 0,
    misses = stats and stats.misses or 0,
    markdown_parses = stats and stats.markdown_parses or 0,
    markdown_inline_parses = stats and stats.markdown_inline_parses or 0,
    cached_lines = stats and stats.cached_lines or 0,
  }
end

return M
