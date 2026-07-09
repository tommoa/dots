local config = require("tom.obsidian_embeds.config")
local contract = require("tom.obsidian_embeds.contract")
local highlight = require("tom.obsidian_embeds.highlight")
local presenter = require("tom.obsidian_embeds.presenter")
local refresh_planner = require("tom.obsidian_embeds.refresh_planner")
local renderer = require("tom.obsidian_embeds.renderer")
local resolver = require("tom.obsidian_embeds.resolver")
local state_mod = require("tom.obsidian_embeds.state")
local tracker = require("tom.obsidian_embeds.tracker")
local util = require("tom.obsidian_embeds.util")

local M = {}

---@type table<integer, true>
local attached = {}
---@type table<integer, any>
local timers = {}
---@type table<integer, ObsidianEmbedsBufferState>
local states = {}
local global_dependencies_attached = false
---@type table<integer, true>
local dependency_buffers = {}
---@type table<integer, string>
local previous_buffer_paths = {}
---@type table<integer, ObsidianEmbedsStats>
local last_stats = {}
---@type table<integer, ObsidianEmbedsRefreshChange[]>
local pending_changes = {}

---@param bufnr? integer
---@return integer
local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---@param bufnr integer
---@return boolean
local function is_enabled(bufnr)
  local enabled = vim.b[bufnr].tom_obsidian_embeds_enabled
  if enabled == nil then
    enabled = config.get().auto
    vim.b[bufnr].tom_obsidian_embeds_enabled = enabled
  end
  return enabled == true
end

---@param bufnr integer
local function stop_timer(bufnr)
  local timer = timers[bufnr]
  if timer then
    timer:stop()
    timer:close()
    timers[bufnr] = nil
  end
end

---@param bufnr integer
---@param first_row integer
---@param old_last_row integer
---@param new_last_row integer
local function queue_changed_range(bufnr, first_row, old_last_row, new_last_row)
  pending_changes[bufnr] = pending_changes[bufnr] or {}
  local old_count = old_last_row - first_row
  local new_count = new_last_row - first_row
  pending_changes[bufnr][#pending_changes[bufnr] + 1] = {
    first_row = first_row,
    last_row = new_last_row - 1,
    line_count_changed = old_count ~= new_count,
  }
end

---@param bufnr integer
---@return ObsidianEmbedsRefreshChange?
local function take_pending_change(bufnr)
  local changes = pending_changes[bufnr]
  pending_changes[bufnr] = nil
  return refresh_planner.merge_changes(changes)
end

---@param api ObsidianEmbedsApi
---@param bufnr? integer
---@param callback fun(api: ObsidianEmbedsApi, bufnr: integer)
local function schedule_call(api, bufnr, callback)
  bufnr = normalize_bufnr(bufnr)
  stop_timer(bufnr)

  local timer = assert(vim.uv.new_timer())
  timers[bufnr] = timer
  timer:start(config.get().debounce_ms, 0, function()
    vim.schedule(function()
      stop_timer(bufnr)
      callback(api, bufnr)
    end)
  end)
end

---@param api ObsidianEmbedsApi
---@param bufnr integer
local function schedule_refresh(api, bufnr)
  schedule_call(api, bufnr, M.refresh)
end

---@param api ObsidianEmbedsApi
---@param bufnr integer
local function schedule_changed_refresh(api, bufnr)
  schedule_call(api, bufnr, M.refresh_changed)
end

---@param bufnr integer
local function cleanup_buffer(bufnr)
  stop_timer(bufnr)
  attached[bufnr] = nil
  dependency_buffers[bufnr] = nil
  previous_buffer_paths[bufnr] = nil
  pending_changes[bufnr] = nil
  states[bufnr] = nil
  tracker.reindex(bufnr, nil)
end

---@param bufnr integer
---@param started_ns? integer
---@param state? ObsidianEmbedsBufferState
local function record_stats(bufnr, started_ns, state)
  if not started_ns then
    return
  end

  local elapsed_ms = (vim.uv.hrtime() - started_ns) / 1000000
  local rendered_rows = 0
  local rendered_lines = 0
  for _, row_state in pairs((state or {}).rows or {}) do
    rendered_rows = rendered_rows + 1
    rendered_lines = rendered_lines + #(row_state.virt_lines or {})
  end

  local index_stats = tracker.stats()
  last_stats[bufnr] = {
    elapsed_ms = elapsed_ms,
    rendered_rows = rendered_rows,
    rendered_lines = rendered_lines,
    path_keys = index_stats.path_keys,
    unresolved_keys = index_stats.unresolved_keys,
    workspaces = index_stats.workspaces,
    indexed_buffers = index_stats.buffers,
    highlight = highlight.cache_stats((state or {}).chunk_cache),
  }

  local opts = config.get()
  if opts.debug and opts.profile_slow_ms and elapsed_ms >= opts.profile_slow_ms then
    vim.notify(
      string.format("Obsidian embeds refresh took %.1fms for %d rendered rows", elapsed_ms, rendered_rows),
      vim.log.levels.INFO
    )
  end
end

---@param bufnr integer
---@return string?
local function buffer_path(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return util.path_key(vim.api.nvim_buf_get_name(bufnr))
end

---@param api ObsidianEmbedsApi
---@param bufnr integer
local function attach_dependency_buffer(api, bufnr)
  if dependency_buffers[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local path = buffer_path(bufnr)
  if not path then
    return
  end

  dependency_buffers[bufnr] = true
  previous_buffer_paths[bufnr] = path
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buffer)
      local dep_path = buffer_path(buffer)
      if dep_path and tracker.has_dependents_for_path(dep_path) then
        tracker.refresh_dependents(dep_path, buffer, function(dependent_bufnr)
          schedule_refresh(api, dependent_bufnr)
        end)
      end
    end,
    on_reload = function(_, buffer)
      local dep_path = buffer_path(buffer)
      if dep_path then
        tracker.refresh_dependents(dep_path, buffer, function(dependent_bufnr)
          schedule_refresh(api, dependent_bufnr)
        end)
      end
    end,
    on_detach = function(_, buffer)
      dependency_buffers[buffer] = nil
      previous_buffer_paths[buffer] = nil
    end,
  })
end

---@param api ObsidianEmbedsApi
---@param state? ObsidianEmbedsBufferState
local function attach_loaded_dependency_buffers(api, state)
  tracker.iter_paths((state or {}).dependencies, function(_, path)
    local bufnr = util.loaded_buf_for_path(path)
    if bufnr then
      attach_dependency_buffer(api, bufnr)
    end
  end)
end

---@param bufnr integer
local function clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, config.ns_id, 0, -1)
  end
  pending_changes[bufnr] = nil
  states[bufnr] = nil
  tracker.reindex(bufnr, nil)
end

---Full refresh: rebuild state from the buffer, render every row, reindex all
---dependencies, then apply marks for the current cursor position.
---@param api ObsidianEmbedsApi
---@param bufnr? integer
function M.refresh(api, bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local started_ns = vim.uv.hrtime()
  stop_timer(bufnr)
  pending_changes[bufnr] = nil
  vim.api.nvim_buf_clear_namespace(bufnr, config.ns_id, 0, -1)
  states[bufnr] = nil
  tracker.reindex(bufnr, nil)

  if not is_enabled(bufnr) or vim.b[bufnr].obsidian_buffer ~= true then
    record_stats(bufnr, started_ns, nil)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor_row = presenter.cursor_row_for_buf(bufnr)
  local requirements = resolver.scan_current_note_requirements(lines)
  local note_opts = resolver.current_note_opts(requirements)
  local workspace_root = util.workspace_root_for_buffer(bufnr, true)
  util.set_workspace_root(workspace_root)
  local current_note
  local current_note_error
  if note_opts then
    local ok, note_or_err = pcall(require("obsidian.note").from_buffer, bufnr, note_opts)
    if ok then
      current_note = note_or_err
    else
      current_note_error = tostring(note_or_err)
    end
  end

  local state = state_mod.new_buffer_state({
    bufnr = bufnr,
    workspace_root = workspace_root,
    base_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)),
    lines = lines,
    cursor_row = cursor_row,
    requirements = requirements,
    current_note_opts = note_opts,
    current_note = current_note,
    current_note_error = current_note_error,
  })

  for row, line in ipairs(lines) do
    local row_state = renderer.render_row_state(api, state, row - 1, line)
    if row_state then
      state.rows[row_state.row] = row_state
    end
  end

  resolver.refresh_same_note_ranges(state)
  tracker.refresh_state_dependencies(state)
  tracker.reindex(bufnr, state)
  attach_loaded_dependency_buffers(api, state)
  for row = 0, #lines - 1 do
    presenter.apply_row_marks(bufnr, state, state.rows[row], cursor_row)
  end
  states[bufnr] = state
  record_stats(bufnr, started_ns, state)
end

---Incremental refresh for same-line edits. The planner decides when local row
---rerendering is safe; structural or line-count changes fall back to refresh().
---@param api ObsidianEmbedsApi
---@param bufnr? integer
function M.refresh_changed(api, bufnr)
  bufnr = normalize_bufnr(bufnr)
  stop_timer(bufnr)
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    api.refresh(bufnr)
    return
  end

  if not is_enabled(bufnr) or vim.b[bufnr].obsidian_buffer ~= true or state.option_generation ~= config.generation() then
    api.refresh(bufnr)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  util.set_workspace_root(state.workspace_root)
  local plan = refresh_planner.plan(state, lines, take_pending_change(bufnr))
  last_stats[bufnr] = last_stats[bufnr] or {}
  last_stats[bufnr].last_plan_kind = plan.kind
  last_stats[bufnr].last_plan_reason = plan.reason
  if plan.kind == "noop" then
    state.changedtick = vim.b[bufnr].changedtick or state.changedtick
    return
  elseif plan.kind == "full" then
    api.refresh(bufnr)
    return
  end

  local cursor_row = presenter.cursor_row_for_buf(bufnr)
  local affected = {}
  for row = plan.first_row, plan.last_row do
    presenter.delete_row_marks(bufnr, state.rows[row])
    state.rows[row] = nil

    local row_state = renderer.render_row_state(api, state, row, lines[row + 1] or "")
    if row_state then
      state.rows[row] = row_state
    end

    state.source_lines[row + 1] = lines[row + 1] or ""
    presenter.collect_mark_affected_rows(state, row, affected)
  end

  state.cursor_row = cursor_row
  state.changedtick = vim.b[bufnr].changedtick or state.changedtick
  tracker.refresh_state_dependencies(state)
  tracker.reindex(bufnr, state)
  attach_loaded_dependency_buffers(api, state)

  local rows = vim.tbl_keys(affected)
  table.sort(rows)
  for _, row in ipairs(rows) do
    presenter.apply_row_marks(bufnr, state, state.rows[row], cursor_row)
  end
  last_stats[bufnr] = vim.tbl_extend("force", last_stats[bufnr] or {}, {
    last_plan_kind = plan.kind,
    last_plan_reason = plan.reason,
    changed_rows = plan.last_row - plan.first_row + 1,
    rendered_rows = vim.tbl_count(state.rows),
    highlight = highlight.cache_stats(state.chunk_cache),
  })
end

---@param _ ObsidianEmbedsApi
---@param bufnr? integer
function M.update_cursor(_, bufnr)
  bufnr = normalize_bufnr(bufnr)
  presenter.update_cursor(bufnr, states[bufnr])
end

---Install global hooks that refresh dependent buffers when target notes change
---or unresolved references become resolvable.
---@param api ObsidianEmbedsApi
function M.ensure_global_dependency_autocmd(api)
  if global_dependencies_attached then
    return
  end

  global_dependencies_attached = true
  local group = vim.api.nvim_create_augroup(config.namespace .. "-dependencies", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group,
    callback = function(ev)
      attach_dependency_buffer(api, ev.buf)
      local path = vim.api.nvim_buf_get_name(ev.buf)
      tracker.refresh_dependents(path, ev.buf, function(bufnr)
        schedule_refresh(api, bufnr)
      end)
      tracker.refresh_unresolved_for_path(path, ev.buf, function(bufnr)
        schedule_refresh(api, bufnr)
      end)
      if vim.b[ev.buf].obsidian_buffer == true then
        local note = require("obsidian.note").from_buffer(ev.buf, { max_lines = math.huge })
        if note then
          tracker.refresh_unresolved_for_note(note, ev.buf, function(bufnr)
            schedule_refresh(api, bufnr)
          end)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost" }, {
    group = group,
    callback = function(ev)
      if tracker.has_dependents_for_path(vim.api.nvim_buf_get_name(ev.buf)) then
        attach_dependency_buffer(api, ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufFilePre" }, {
    group = group,
    callback = function(ev)
      previous_buffer_paths[ev.buf] = buffer_path(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufFilePost" }, {
    group = group,
    callback = function(ev)
      local old_path = previous_buffer_paths[ev.buf]
      local new_path = buffer_path(ev.buf)
      previous_buffer_paths[ev.buf] = new_path
      for _, path in ipairs({ old_path, new_path }) do
        if path then
          tracker.refresh_dependents(path, ev.buf, function(bufnr)
            schedule_refresh(api, bufnr)
          end)
          tracker.refresh_unresolved_for_path(path, ev.buf, function(bufnr)
            schedule_refresh(api, bufnr)
          end)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "User" }, {
    group = group,
    pattern = "ObsidianNoteEnter",
    callback = function(ev)
      attach_dependency_buffer(api, ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "User" }, {
    group = group,
    pattern = "ObsidianNoteCreate",
    callback = function(ev)
      local note = ev.data and ev.data.note
      if note then
        tracker.refresh_unresolved_for_note(note, ev.buf, function(bufnr)
          schedule_refresh(api, bufnr)
        end)
      end
    end,
  })
end

---@param api ObsidianEmbedsApi
---@param bufnr integer
---@return boolean?
local function attach_buffer_updates(api, bufnr)
  return vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buffer, _, first_row, old_last_row, new_last_row)
      queue_changed_range(buffer, first_row, old_last_row, new_last_row)
      schedule_changed_refresh(api, buffer)
    end,
    on_reload = function(_, buffer)
      pending_changes[buffer] = nil
      schedule_refresh(api, buffer)
    end,
    on_detach = function(_, buffer)
      cleanup_buffer(buffer)
    end,
  })
end

---@param api ObsidianEmbedsApi
---@param bufnr? integer
function M.toggle(api, bufnr)
  bufnr = normalize_bufnr(bufnr)
  vim.b[bufnr].tom_obsidian_embeds_enabled = not is_enabled(bufnr)
  if is_enabled(bufnr) then
    api.refresh(bufnr)
  else
    clear(bufnr)
  end
end

---Attach embeds to an Obsidian buffer. The api parameter is the public module
---table, passed through so tests can wrap render/refresh functions.
---@param api ObsidianEmbedsApi
---@param bufnr? integer
function M.attach(api, bufnr)
  contract.assert_obsidian()
  bufnr = normalize_bufnr(bufnr)
  if attached[bufnr] then
    api.refresh(bufnr)
    return
  end

  attached[bufnr] = true
  vim.b[bufnr].tom_obsidian_embeds_enabled = config.get().auto
  attach_buffer_updates(api, bufnr)
  if vim.api.nvim_get_current_buf() == bufnr then
    presenter.apply_window_options()
  end

  local group = vim.api.nvim_create_augroup(config.namespace .. "-" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      presenter.apply_window_options()
      schedule_refresh(api, ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      schedule_refresh(api, ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      api.update_cursor(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    callback = function(ev)
      cleanup_buffer(ev.buf)
    end,
  })

  vim.api.nvim_buf_create_user_command(bufnr, "ObsidianEmbedsToggle", function()
    api.toggle(bufnr)
  end, { force = true, desc = "Toggle Obsidian note embeds" })

  vim.api.nvim_buf_create_user_command(bufnr, "ObsidianEmbedsRefresh", function()
    api.refresh(bufnr)
  end, { force = true, desc = "Refresh Obsidian note embeds" })

  if config.get().debug then
    vim.api.nvim_buf_create_user_command(bufnr, "ObsidianEmbedsStats", function()
      vim.print(last_stats[bufnr] or {})
    end, { force = true, desc = "Show Obsidian embed render stats" })
  end

  vim.keymap.set("n", "<leader>vE", function()
    api.toggle(bufnr)
  end, { buffer = bufnr, desc = "Toggle Obsidian note embeds" })

  M.ensure_global_dependency_autocmd(api)
  attach_dependency_buffer(api, bufnr)
  api.refresh(bufnr)
end

---@param bufnr? integer
---@return ObsidianEmbedsStats
function M.stats(bufnr)
  bufnr = normalize_bufnr(bufnr)
  return last_stats[bufnr] or {}
end

return M
