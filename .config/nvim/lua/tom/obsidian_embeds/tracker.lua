local state = require("tom.obsidian_embeds.state")
local util = require("tom.obsidian_embeds.util")

local M = {}

---@alias ObsidianEmbedsScheduleRefresh fun(bufnr: integer)
---@alias ObsidianEmbedsPathIterator fun(workspace: string, path: string)
---@alias ObsidianEmbedsDependentIndex table<string, table<string, table<integer, true>>>

---@type ObsidianEmbedsDependentIndex
local path_index = {}
---@type ObsidianEmbedsDependentIndex
local unresolved_index = {}
---@type table<integer, ObsidianEmbedsDependencySet>
local buffer_dependencies = {}

---@return ObsidianEmbedsDependencySet
function M.new_dependency_set()
  return state.new_dependency_set()
end

---@param index ObsidianEmbedsDependentIndex
---@param workspace string
---@param key string
---@return table<integer, true>
local function ensure_bucket(index, workspace, key)
  index[workspace] = index[workspace] or {}
  index[workspace][key] = index[workspace][key] or {}
  return index[workspace][key]
end

---@param target ObsidianEmbedsPathIndex
---@param workspace? string
---@param key? string
local function add_nested_key(target, workspace, key)
  if not (workspace and key) then
    return
  end
  target[workspace] = target[workspace] or {}
  target[workspace][key] = true
end

---@param target ObsidianEmbedsPathIndex
---@param source? ObsidianEmbedsPathIndex
local function merge_nested_keys(target, source)
  for workspace, keys in pairs(source or {}) do
    for key in pairs(keys or {}) do
      add_nested_key(target, workspace, key)
    end
  end
end

---@param target? ObsidianEmbedsDependencySet
---@param dependencies? ObsidianEmbedsDependencySet
function M.merge_dependency_set(target, dependencies)
  if not target then
    return
  end

  target.paths = target.paths or {}
  target.unresolved = target.unresolved or {}
  merge_nested_keys(target.paths, (dependencies or {}).paths)
  merge_nested_keys(target.unresolved, (dependencies or {}).unresolved)
end

---@param dependencies? ObsidianEmbedsDependencySet
---@return ObsidianEmbedsDependencySet
function M.copy_dependency_set(dependencies)
  local out = M.new_dependency_set()
  M.merge_dependency_set(out, dependencies)
  return out
end

---@param dependencies ObsidianEmbedsDependencySet
---@param path string
local function add_path_dependency(dependencies, path)
  path = util.path_key(path)
  if not path then
    return
  end
  local workspace = util.workspace_root_for_path(path, true)
  add_nested_key(dependencies.paths, workspace, path)
end

---@param dependencies ObsidianEmbedsDependencySet
---@param workspace string
---@param target string
local function add_unresolved_dependency(dependencies, workspace, target)
  workspace = assert(workspace, "tom.obsidian_embeds requires workspace_root for unresolved dependency tracking")
  local key = util.unresolved_key(target)
  if key then
    add_nested_key(dependencies.unresolved, workspace, key)
  end
end

---@param ctx? ObsidianEmbedsRenderContext
---@param note ObsidianEmbedsNote
function M.track_dependency(ctx, note)
  if not ctx then
    return
  end

  local path = util.note_path_key(note)
  if not path then
    return
  end

  if ctx.dependencies then
    add_path_dependency(ctx.dependencies, path)
  end
  if ctx.render_dependencies then
    add_path_dependency(ctx.render_dependencies, path)
  end
end

---@param ctx? ObsidianEmbedsRenderContext
---@param target string
function M.track_unresolved(ctx, target)
  if not ctx then
    return
  end

  if ctx.dependencies then
    add_unresolved_dependency(ctx.dependencies, ctx.workspace_root, target)
  end
  if ctx.render_dependencies then
    add_unresolved_dependency(ctx.render_dependencies, ctx.workspace_root, target)
  end
end

---@param buffer_state ObsidianEmbedsBufferState
function M.refresh_state_dependencies(buffer_state)
  local dependencies = M.new_dependency_set()
  for _, row_state in pairs(buffer_state.rows) do
    M.merge_dependency_set(dependencies, row_state.dependencies)
  end
  buffer_state.dependencies = dependencies
end

---@param index ObsidianEmbedsDependentIndex
---@param bufnr integer
---@param dependencies? ObsidianEmbedsPathIndex
local function remove_buffer_from_index(index, bufnr, dependencies)
  for workspace, keys in pairs(dependencies or {}) do
    for key in pairs(keys or {}) do
      if index[workspace] and index[workspace][key] then
        index[workspace][key][bufnr] = nil
        if next(index[workspace][key]) == nil then
          index[workspace][key] = nil
        end
      end
    end
    if index[workspace] and next(index[workspace]) == nil then
      index[workspace] = nil
    end
  end
end

---@param index ObsidianEmbedsDependentIndex
---@param bufnr integer
---@param dependencies? ObsidianEmbedsPathIndex
local function add_buffer_to_index(index, bufnr, dependencies)
  for workspace, keys in pairs(dependencies or {}) do
    for key in pairs(keys or {}) do
      ensure_bucket(index, workspace, key)[bufnr] = true
    end
  end
end

---Replace one buffer's dependency index entries atomically. Passing nil removes
---the buffer from all dependency indexes.
---@param bufnr integer
---@param buffer_state? ObsidianEmbedsBufferState
function M.reindex(bufnr, buffer_state)
  local old = buffer_dependencies[bufnr]
  if old then
    remove_buffer_from_index(path_index, bufnr, old.paths)
    remove_buffer_from_index(unresolved_index, bufnr, old.unresolved)
    buffer_dependencies[bufnr] = nil
  end

  if not buffer_state then
    return
  end

  local dependencies = M.copy_dependency_set(buffer_state.dependencies)
  buffer_dependencies[bufnr] = dependencies
  add_buffer_to_index(path_index, bufnr, dependencies.paths)
  add_buffer_to_index(unresolved_index, bufnr, dependencies.unresolved)
end

---@param dependencies? ObsidianEmbedsDependencySet
---@param callback ObsidianEmbedsPathIterator
function M.iter_paths(dependencies, callback)
  for workspace, paths in pairs((dependencies or {}).paths or {}) do
    for path in pairs(paths or {}) do
      callback(workspace, path)
    end
  end
end

---@param index ObsidianEmbedsDependentIndex
---@param workspace string
---@param key string
---@param origin_bufnr integer
---@param schedule_refresh ObsidianEmbedsScheduleRefresh
---@param seen table<integer, true>
local function schedule_indexed(index, workspace, key, origin_bufnr, schedule_refresh, seen)
  local buffers = index[workspace] and index[workspace][key]
  if not buffers then
    return
  end

  for bufnr in pairs(buffers) do
    if bufnr ~= origin_bufnr and vim.api.nvim_buf_is_valid(bufnr) and not seen[bufnr] then
      seen[bufnr] = true
      schedule_refresh(bufnr)
    end
  end
end

---@param path string
---@param origin_bufnr integer
---@param schedule_refresh ObsidianEmbedsScheduleRefresh
function M.refresh_dependents(path, origin_bufnr, schedule_refresh)
  path = util.path_key(path)
  local workspace = util.workspace_root_for_path(path, false)
  if not (path and workspace) then
    return
  end

  schedule_indexed(path_index, workspace, path, origin_bufnr, schedule_refresh, {})
end

---@param workspace? string
---@param keys table<string, true>
---@param origin_bufnr integer
---@param schedule_refresh ObsidianEmbedsScheduleRefresh
function M.refresh_unresolved_keys(workspace, keys, origin_bufnr, schedule_refresh)
  if not workspace then
    return
  end

  local seen = {}
  for key in pairs(keys or {}) do
    schedule_indexed(unresolved_index, workspace, key, origin_bufnr, schedule_refresh, seen)
  end
end

---@param note ObsidianEmbedsNote
---@param origin_bufnr integer
---@param schedule_refresh ObsidianEmbedsScheduleRefresh
function M.refresh_unresolved_for_note(note, origin_bufnr, schedule_refresh)
  local path = util.note_path_key(note)
  local workspace = util.workspace_root_for_path(path, false)
  M.refresh_unresolved_keys(workspace, util.note_reference_keys(note), origin_bufnr, schedule_refresh)
end

---@param path string
---@param origin_bufnr integer
---@param schedule_refresh ObsidianEmbedsScheduleRefresh
function M.refresh_unresolved_for_path(path, origin_bufnr, schedule_refresh)
  local workspace = util.workspace_root_for_path(path, false)
  M.refresh_unresolved_keys(workspace, util.path_reference_keys(path), origin_bufnr, schedule_refresh)
end

---@param path string
---@return boolean
function M.has_dependents_for_path(path)
  path = util.path_key(path)
  local workspace = util.workspace_root_for_path(path, false)
  return path ~= nil and workspace ~= nil and path_index[workspace] ~= nil and path_index[workspace][path] ~= nil
end

---@param index ObsidianEmbedsDependentIndex
---@return integer workspaces
---@return integer keys
local function count_nested(index)
  local workspaces = 0
  local keys = 0
  for _, workspace_index in pairs(index) do
    workspaces = workspaces + 1
    for _ in pairs(workspace_index) do
      keys = keys + 1
    end
  end
  return workspaces, keys
end

---@return { workspaces: integer, path_keys: integer, unresolved_keys: integer, buffers: integer }
function M.stats()
  local path_workspaces, paths = count_nested(path_index)
  local unresolved_workspaces, unresolved = count_nested(unresolved_index)
  local buffers = 0
  for _ in pairs(buffer_dependencies) do
    buffers = buffers + 1
  end
  return {
    workspaces = math.max(path_workspaces, unresolved_workspaces),
    path_keys = paths,
    unresolved_keys = unresolved,
    buffers = buffers,
  }
end

---@return nil
function M.reset()
  path_index = {}
  unresolved_index = {}
  buffer_dependencies = {}
end

return M
