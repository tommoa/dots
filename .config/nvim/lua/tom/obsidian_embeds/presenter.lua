local config = require("tom.obsidian_embeds.config")

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

---@param bufnr integer
---@return integer?
function M.cursor_row_for_buf(bufnr)
  if not opts().hide_source or opts().hide_source_on_cursor_line or vim.api.nvim_get_current_buf() ~= bufnr then
    return nil
  end

  return vim.api.nvim_win_get_cursor(0)[1] - 1
end

---@param row integer
---@param cursor_row? integer
---@return boolean
local function source_hidden(row, cursor_row)
  return opts().hide_source and (cursor_row == nil or row ~= cursor_row)
end

---@param row_state? ObsidianEmbedsRowState
---@return boolean
local function row_has_visible_embed_source(row_state)
  return row_state and #row_state.refs > 0
end

---@param row_state? ObsidianEmbedsRowState
---@return boolean
function M.row_can_conceal_line(row_state)
  return row_state
    and row_state.exact
    and row_has_visible_embed_source(row_state)
    and row_state.virt_lines[1] ~= nil
end

---@param row_state? ObsidianEmbedsRowState
---@param cursor_row? integer
---@return boolean
local function row_uses_concealed_line(row_state, cursor_row)
  return M.row_can_conceal_line(row_state)
    and source_hidden(row_state.row, cursor_row)
end

---@param state ObsidianEmbedsBufferState
---@param row integer
---@param cursor_row? integer
---@return boolean
local function is_first_concealed_row_in_run(state, row, cursor_row)
  return row_uses_concealed_line(state.rows[row], cursor_row)
    and not row_uses_concealed_line(state.rows[row - 1], cursor_row)
end

---Collect consecutive exact-embed rows into one virt_lines block. Neovim cannot
---show virt_lines on a row that is itself fully line-concealed, so the mark is
---anchored above the next visible row.
---@param state ObsidianEmbedsBufferState
---@param row integer
---@param cursor_row? integer
---@return ObsidianEmbedsVirtLine[] virt_lines
---@return integer anchor
local function concealed_run_virt_lines(state, row, cursor_row)
  local virt_lines = {}
  local anchor = row
  while anchor < state.line_count and row_uses_concealed_line(state.rows[anchor], cursor_row) do
    append_lines(virt_lines, state.rows[anchor].virt_lines)
    anchor = anchor + 1
  end
  return virt_lines, anchor
end

---@param bufnr integer
---@param row_state? ObsidianEmbedsRowState
function M.delete_row_marks(bufnr, row_state)
  if not row_state then
    return
  end

  if row_state.render_mark then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, config.ns_id, row_state.render_mark)
    row_state.render_mark = nil
  end

  for _, mark_id in ipairs(row_state.conceal_marks or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, config.ns_id, mark_id)
  end
  row_state.conceal_marks = {}
end

---@param base table
---@return table
local function extmark_opts(base)
  base.priority = opts().priority
  return base
end

---@param base table
---@return table
local function virt_lines_extmark_opts(base)
  base = extmark_opts(base)
  if opts().virt_lines_overflow then
    base.virt_lines_overflow = opts().virt_lines_overflow
  end
  if opts().virt_lines_leftcol ~= nil then
    base.virt_lines_leftcol = opts().virt_lines_leftcol
  end
  return base
end

---Apply render and conceal marks for one row. Exact single-embed lines may hide
---the whole source line; non-exact lines only conceal the embed ref ranges.
---@param bufnr integer
---@param state ObsidianEmbedsBufferState
---@param row_state? ObsidianEmbedsRowState
---@param cursor_row? integer
function M.apply_row_marks(bufnr, state, row_state, cursor_row)
  if not row_state then
    return
  end

  M.delete_row_marks(bufnr, row_state)

  if row_uses_concealed_line(row_state, cursor_row) then
    local mark_id = vim.api.nvim_buf_set_extmark(bufnr, config.ns_id, row_state.row, 0, extmark_opts({
      end_row = row_state.row,
      end_col = -1,
      strict = false,
      conceal_lines = "",
    }))
    row_state.conceal_marks[#row_state.conceal_marks + 1] = mark_id
  elseif source_hidden(row_state.row, cursor_row) then
    for _, ref in ipairs(row_state.refs) do
      local mark_id = vim.api.nvim_buf_set_extmark(bufnr, config.ns_id, row_state.row, ref.range.start_col, extmark_opts({
        end_row = row_state.row,
        end_col = ref.range.end_col,
        conceal = "",
      }))
      row_state.conceal_marks[#row_state.conceal_marks + 1] = mark_id
    end
  end

  if #row_state.virt_lines == 0 then
    return
  end

  if row_uses_concealed_line(row_state, cursor_row) then
    if not is_first_concealed_row_in_run(state, row_state.row, cursor_row) then
      return
    end

    local virt_lines, anchor = concealed_run_virt_lines(state, row_state.row, cursor_row)
    row_state.render_mark = vim.api.nvim_buf_set_extmark(bufnr, config.ns_id, anchor, 0, virt_lines_extmark_opts({
      virt_lines = virt_lines,
      virt_lines_above = true,
    }))
  else
    row_state.render_mark = vim.api.nvim_buf_set_extmark(bufnr, config.ns_id, row_state.row, 0, virt_lines_extmark_opts({
      virt_lines = row_state.virt_lines,
    }))
  end
end

---@param state ObsidianEmbedsBufferState
---@param row? integer
---@param affected table<integer, true>
local function collect_cursor_affected_rows(state, row, affected)
  if row == nil then
    return
  end

  affected[row] = true

  local previous = row - 1
  while previous >= 0 and M.row_can_conceal_line(state.rows[previous]) do
    affected[previous] = true
    previous = previous - 1
  end

  local next_row = row + 1
  while next_row < state.line_count and M.row_can_conceal_line(state.rows[next_row]) do
    affected[next_row] = true
    next_row = next_row + 1
  end
end

---@param state ObsidianEmbedsBufferState
---@param row integer
---@param affected table<integer, true>
function M.collect_mark_affected_rows(state, row, affected)
  affected[row] = true

  local previous = row - 1
  while previous >= 0 and M.row_can_conceal_line(state.rows[previous]) do
    affected[previous] = true
    previous = previous - 1
  end

  local next_row = row + 1
  while next_row < state.line_count and M.row_can_conceal_line(state.rows[next_row]) do
    affected[next_row] = true
    next_row = next_row + 1
  end
end

---@param bufnr integer
---@param state? ObsidianEmbedsBufferState
function M.update_cursor(bufnr, state)
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local cursor_row = M.cursor_row_for_buf(bufnr)
  if cursor_row == state.cursor_row then
    return
  end

  local previous_row = state.cursor_row
  state.cursor_row = cursor_row

  local affected = {}
  collect_cursor_affected_rows(state, previous_row, affected)
  collect_cursor_affected_rows(state, cursor_row, affected)

  local rows = vim.tbl_keys(affected)
  table.sort(rows)
  for _, row in ipairs(rows) do
    M.apply_row_marks(bufnr, state, state.rows[row], cursor_row)
  end
end

---@return nil
function M.apply_window_options()
  if opts().set_conceallevel then
    vim.wo.conceallevel = 2
  end
end

return M
