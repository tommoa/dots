local M = {}

---@param path string
---@param value any
local function assert_function(path, value)
  assert(type(value) == "function", "tom.obsidian_embeds requires " .. path)
end

---Verify the subset of obsidian.nvim internals this renderer depends on.
---@return nil
function M.assert_obsidian()
  assert(_G.Obsidian ~= nil, "tom.obsidian_embeds requires obsidian.nvim setup before use")

  assert_function("obsidian.parse.refs.extract", require("obsidian.parse.refs").extract)
  assert_function("obsidian.search.resolve_note", require("obsidian.search").resolve_note)
  assert_function("obsidian.note.from_buffer", require("obsidian.note").from_buffer)
  assert_function("obsidian.note.from_file", require("obsidian.note").from_file)
  assert_function("obsidian.attachment.is_attachment_path", require("obsidian.attachment").is_attachment_path)
  assert_function("obsidian.util.is_uri", require("obsidian.util").is_uri)
  assert_function("obsidian.api.find_workspace", require("obsidian.api").find_workspace)
  assert_function("obsidian.register_command", require("obsidian").register_command)
end

return M
