-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-dependencies-smoke.lua

local testlib = dofile(vim.fn.expand("~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-testlib.lua"))

local function fail(message)
  error(message, 0)
end

local function assert_true(value, message)
  if not value then
    fail(message)
  end
end

local function assert_contains(haystack, needle, message)
  if not haystack:find(needle, 1, true) then
    fail(message .. "\nexpected to find: " .. needle .. "\nin: " .. haystack)
  end
end

local function write_file(path, lines)
  local file = assert(io.open(path, "w"))
  file:write(table.concat(lines, "\n"))
  file:write("\n")
  file:close()
end

testlib.setup_runtime()

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.mkdir(root .. "/.obsidian", "p")

write_file(root .. "/Target.md", {
  "# Target",
  "initial target body",
})

write_file(root .. "/DeleteMe.md", {
  "delete me body",
})

write_file(root .. "/Main.md", {
  "![[DeleteMe]]",
  "![[Target]]",
  "![[CreatedLater]]",
  "![[CreatedLater]]",
})

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    {
      name = "dependency-smoke",
      path = root,
    },
  },
  picker = {
    name = false,
  },
  ui = {
    enable = false,
  },
}

local embeds = require("tom.obsidian_embeds")
embeds.setup {
  debounce_ms = 10,
}

vim.cmd.edit(root .. "/Main.md")
local main_bufnr = vim.api.nvim_get_current_buf()
vim.b[main_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
embeds.attach(main_bufnr)
embeds.refresh(main_bufnr)

local ns = vim.api.nvim_create_namespace(embeds.namespace)

-- Scenario: dependency indexes track rendered targets, unsaved loaded buffers,
-- deleted source rows, and unresolved refs that become resolvable later.
local function rendered_text(bufnr)
  local lines = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    local details = mark[4]
    for _, virt_line in ipairs(details.virt_lines or {}) do
      local parts = {}
      for _, chunk in ipairs(virt_line) do
        parts[#parts + 1] = chunk[1]
      end
      lines[#lines + 1] = table.concat(parts, "")
    end
  end
  return table.concat(lines, "\n")
end

assert_contains(rendered_text(main_bufnr), "delete me body", "deletion regression fixture did not render")
assert_contains(rendered_text(main_bufnr), "initial target body", "initial dependency did not render")
assert_contains(rendered_text(main_bufnr), "Embed not found: CreatedLater", "missing dependency warning did not render")
vim.api.nvim_buf_set_lines(main_bufnr, 0, 1, false, {})
embeds.refresh_changed(main_bufnr)
assert_true(
  not rendered_text(main_bufnr):find("delete me body", 1, true),
  "deleting an embed line without replacement should clear its rendered output"
)
vim.api.nvim_buf_set_lines(main_bufnr, 1, 2, false, { "first missing embed removed" })
embeds.refresh_changed(main_bufnr)

vim.cmd.edit(root .. "/Target.md")
local target_bufnr = vim.api.nvim_get_current_buf()
vim.b[target_bufnr].obsidian_buffer = true
vim.api.nvim_buf_set_lines(target_bufnr, 1, 2, false, { "unsaved target body" })
local unsaved_refresh = vim.wait(1000, function()
  return rendered_text(main_bufnr):find("unsaved target body", 1, true) ~= nil
end, 20)
assert_true(unsaved_refresh, "unsaved target buffer edit should refresh dependent embeds")
assert_true(
  not rendered_text(main_bufnr):find("initial target body", 1, true),
  "dependent render should prefer loaded buffer contents over disk"
)

vim.cmd.edit(root .. "/CreatedLater.md")
local created_bufnr = vim.api.nvim_get_current_buf()
vim.b[created_bufnr].obsidian_buffer = true
vim.api.nvim_buf_set_lines(created_bufnr, 0, -1, false, { "created later body" })
vim.cmd.write()
local created_refresh = vim.wait(1000, function()
  return rendered_text(main_bufnr):find("created later body", 1, true) ~= nil
end, 20)
assert_true(created_refresh, "creating a previously missing target should refresh unresolved embeds")

print("obsidian embeds dependency smoke test passed")
