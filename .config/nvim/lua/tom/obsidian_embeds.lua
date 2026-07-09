local config = require("tom.obsidian_embeds.config")
local contract = require("tom.obsidian_embeds.contract")
local manager = require("tom.obsidian_embeds.manager")
local renderer = require("tom.obsidian_embeds.renderer")

---@type ObsidianEmbedsApi
local M = {}

---Render a single embed reference using the public API table for recursive calls.
---@param ref ObsidianEmbedsRef
---@param ctx ObsidianEmbedsRenderContext
---@return ObsidianEmbedsVirtLine[]?
function M.render_ref(ref, ctx)
  return renderer.render_ref(M, ref, ctx)
end

---Render a single embed reference, converting unexpected errors into warning lines.
---@param ref ObsidianEmbedsRef
---@param ctx ObsidianEmbedsRenderContext
---@return ObsidianEmbedsVirtLine[]?
function M.safe_render_ref(ref, ctx)
  return renderer.safe_render_ref(M, ref, ctx)
end

---@param bufnr? integer
function M.refresh(bufnr)
  return manager.refresh(M, bufnr)
end

---@param bufnr? integer
function M.refresh_changed(bufnr)
  return manager.refresh_changed(M, bufnr)
end

---@param bufnr? integer
function M.update_cursor(bufnr)
  return manager.update_cursor(M, bufnr)
end

---@param bufnr? integer
---@return ObsidianEmbedsStats
function M.stats(bufnr)
  return manager.stats(bufnr)
end

---@param bufnr? integer
function M.toggle(bufnr)
  return manager.toggle(M, bufnr)
end

---@param bufnr? integer
function M.attach(bufnr)
  return manager.attach(M, bufnr)
end

---@param user_opts? table
function M.setup(user_opts)
  config.setup(user_opts)
  contract.assert_obsidian()
  manager.ensure_global_dependency_autocmd(M)
end

M.namespace = config.namespace

return M
