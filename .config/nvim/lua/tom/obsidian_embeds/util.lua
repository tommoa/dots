local M = {}

---@class ObsidianEmbedsWorkspace
---@field root string

---@param target? string
---@return string
function M.decode_target(target)
  return vim.uri_decode(target or "")
end

---@param path? string
---@return string?
function M.path_key(path)
  if not path or path == "" then
    return nil
  end
  return vim.fs.normalize(tostring(path))
end

---@param path string
---@return integer?
function M.loaded_buf_for_path(path)
  path = M.path_key(path)
  if not path then
    return nil
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      local name = M.path_key(vim.api.nvim_buf_get_name(bufnr))
      if name == path then
        return bufnr
      end
    end
  end
  return nil
end

---@param path? string
---@param required boolean
---@return string?
function M.workspace_root_for_path(path, required)
  path = M.path_key(path)
  if not path then
    if required then
      error("Obsidian embeds requires a valid path for workspace lookup", 2)
    end
    return nil
  end

  local workspace = require("obsidian.api").find_workspace(path)
  if workspace and workspace.root then
    return M.path_key(tostring(workspace.root))
  end

  if required then
    error("Obsidian embeds requires an Obsidian workspace for path: " .. path, 2)
  end
  return nil
end

---@param root? string
---@return ObsidianEmbedsWorkspace?
function M.workspace_for_root(root)
  root = M.path_key(root)
  if not (_G.Obsidian and _G.Obsidian.workspaces) then
    return nil
  end

  for _, workspace in ipairs(_G.Obsidian.workspaces) do
    if workspace.root and M.path_key(tostring(workspace.root)) == root then
      return workspace
    end
  end
  return nil
end

---@param root string
---@return ObsidianEmbedsWorkspace
function M.set_workspace_root(root)
  local workspace = M.workspace_for_root(root)
  assert(workspace, "Obsidian embeds requires a configured workspace for root: " .. tostring(root))

  if not (_G.Obsidian and _G.Obsidian.workspace and M.path_key(tostring(_G.Obsidian.workspace.root)) == M.path_key(root)) then
    require("obsidian.workspace").set(workspace)
  end
  return workspace
end

---@param bufnr integer
---@param required boolean
---@return string?
function M.workspace_root_for_buffer(bufnr, required)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    if required then
      error("Obsidian embeds requires a valid buffer for workspace lookup", 2)
    end
    return nil
  end
  return M.workspace_root_for_path(vim.api.nvim_buf_get_name(bufnr), required)
end

---@param target? string
---@return string?
function M.unresolved_key(target)
  target = M.decode_target(target)
  if target == "" then
    return nil
  end
  return (target:gsub("%.md$", "")):lower()
end

---@param keys table<string, true>
---@param value? string
local function add_key(keys, value)
  local key = M.unresolved_key(value)
  if key then
    keys[key] = true
  end
end

---Return every reference key that could satisfy an unresolved embed for a note:
---id/title/alias plus obsidian.nvim's own reference ids and encoded paths.
---@param note? ObsidianEmbedsNote
---@return table<string, true>
function M.note_reference_keys(note)
  local keys = {}
  if not note then
    return keys
  end

  add_key(keys, note.id)
  add_key(keys, note.title)
  if note.display_name then
    add_key(keys, note:display_name())
  end

  for _, alias in ipairs(note.aliases or {}) do
    add_key(keys, alias)
  end

  if note.reference_ids then
    for _, ref in ipairs(note:reference_ids({ lowercase = false }) or {}) do
      add_key(keys, ref)
    end
  end

  if note.get_reference_paths then
    for _, ref in ipairs(note:get_reference_paths({ urlencode = true }) or {}) do
      add_key(keys, ref)
    end
  end

  return keys
end

---@param path? string
---@return table<string, true>
function M.path_reference_keys(path)
  local keys = {}
  path = M.path_key(path)
  if not path then
    return keys
  end

  add_key(keys, path)
  add_key(keys, vim.fs.basename(path))
  add_key(keys, (vim.fs.basename(path):gsub("%.md$", "")))

  local root = M.workspace_root_for_path(path, false)
  if root and vim.startswith(path, root .. "/") then
    local rel = path:sub(#root + 2)
    add_key(keys, rel)
    add_key(keys, rel:gsub("%.md$", ""))
  end

  return keys
end

---@param note? ObsidianEmbedsNote
---@return string?
function M.note_path_key(note)
  return note and note.path and M.path_key(tostring(note.path)) or nil
end

---Signature used in render-cache keys. Loaded buffers use changedtick so unsaved
---target edits invalidate cached renders before the file is written.
---@param note? ObsidianEmbedsNote
---@return string
function M.note_signature(note)
  local path = M.note_path_key(note)
  local loaded_buf = path and M.loaded_buf_for_path(path) or nil
  if loaded_buf then
    return "buf:" .. tostring(loaded_buf) .. ":" .. tostring(vim.b[loaded_buf].changedtick or 0)
  end

  if note and note.bufnr and vim.api.nvim_buf_is_valid(note.bufnr) then
    return "buf:" .. tostring(note.bufnr) .. ":" .. tostring(vim.b[note.bufnr].changedtick or 0)
  end

  if not path then
    return "path:"
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then
    return "path:" .. path .. ":missing"
  end

  local mtime = stat.mtime or {}
  return table.concat({ "path", path, tostring(stat.size or 0), tostring(mtime.sec or 0), tostring(mtime.nsec or 0) }, ":")
end

return M
