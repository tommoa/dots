local M = {}

---@class ObsidianEmbedsConfig
---@field auto boolean Attach buffers with embeds enabled by default.
---@field max_depth integer Maximum nested embed depth before rendering a warning.
---@field debounce_ms integer Delay before queued refreshes run.
---@field include_frontmatter boolean Include note frontmatter in whole-note embeds.
---@field hl_group string Default highlight group for rendered text.
---@field warning_hl_group string Highlight group for rendered warnings.
---@field hide_source boolean Conceal embed source markup while showing rendered content.
---@field hide_source_on_cursor_line boolean Keep source concealed even on the cursor line.
---@field trim boolean Trim leading and trailing blank lines from rendered embeds.
---@field nested_marker string Marker added to nested rendered lines.
---@field virt_lines_overflow? string
---@field virt_lines_leftcol? boolean
---@field priority integer Extmark priority for render and conceal marks.
---@field set_conceallevel boolean Set the current window conceallevel when attaching.
---@field debug boolean Enable debug-only commands and slow refresh notifications.
---@field profile_slow_ms integer Minimum refresh time to report when debug is enabled.

M.namespace = "tom.obsidian_embeds"
M.ns_id = vim.api.nvim_create_namespace(M.namespace)

---@type ObsidianEmbedsConfig
local defaults = {
  auto = true,
  max_depth = 3,
  debounce_ms = 150,
  include_frontmatter = false,
  hl_group = "Comment",
  warning_hl_group = "WarningMsg",
  hide_source = true,
  hide_source_on_cursor_line = false,
  trim = true,
  nested_marker = "> ",
  virt_lines_overflow = "trunc",
  virt_lines_leftcol = false,
  priority = 110,
  set_conceallevel = false,
  debug = false,
  profile_slow_ms = 50,
}

local opts = vim.deepcopy(defaults)
local generation = 0

---@return ObsidianEmbedsConfig
function M.get()
  return opts
end

---@return integer
function M.generation()
  return generation
end

---@param user_opts? table
function M.setup(user_opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
  generation = generation + 1
end

return M
