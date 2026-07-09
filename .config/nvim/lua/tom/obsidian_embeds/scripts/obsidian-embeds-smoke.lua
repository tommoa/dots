-- Run with:
--   nvim --headless -l ~/.config/nvim/lua/tom/obsidian_embeds/scripts/obsidian-embeds-smoke.lua

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
  "---",
  "id: target",
  "---",
  "Intro line",
  "A [[Wiki target|wiki label]] and [markdown label](Target.md) with `code` and **bold**.",
  "",
  "## Section",
  "Section line",
  "",
  "Block paragraph ^block",
  "",
  "###### 6 ",
  "Level six verse",
})

write_file(root .. "/Nested.md", {
  "before nested",
  "![[Target#Section]]",
  "after nested",
})

vim.fn.mkdir(root .. "/Outer", "p")
vim.fn.mkdir(root .. "/Outer/NestedDir", "p")
write_file(root .. "/Outer/Parent.md", {
  "parent before",
  "![[./NestedDir/Child]]",
  "parent after",
})

write_file(root .. "/Outer/NestedDir/Child.md", {
  "child relative body",
})

write_file(root .. "/CacheOuter.md", {
  "before cache inner",
  "![[CacheInner]]",
  "after cache inner",
})

write_file(root .. "/CacheInner.md", {
  "cache inner initial",
})

write_file(root .. "/Trimmed.md", {
  "",
  "",
  "Trim first",
  "",
  "Trim last",
  "",
})

write_file(root .. "/AliasNote.md", {
  "# Original Heading",
  "Alias body remains",
  "## Child Heading",
})

write_file(root .. "/PlainAlias.md", {
  "Plain first line",
  "Plain body remains",
})

write_file(root .. "/OrderedFirst.md", {
  "first ordered body",
})

write_file(root .. "/OrderedSecond.md", {
  "second ordered body",
})

write_file(root .. "/CycleA.md", { "![[CycleB]]" })
write_file(root .. "/CycleB.md", { "![[CycleA]]" })
write_file(root .. "/image.png", { "not really a png" })
write_file(root .. "/Main.md", {
  "![[Target]]",
  "![[Target#Section]]",
  "![[Target#6|Verse 6 Alias]]",
  "![[Target#Section#6|Nested Verse Alias]]",
  "![[Target#^block]]",
  "![[Nested]]",
  "![[Outer/Parent]]",
  "![[Trimmed]]",
  "![[AliasNote|Display Alias]]",
  "![[PlainAlias|Ignored Alias]]",
  "![[Missing]]",
  "![[image.png]]",
  "![[CycleA]]",
  "![[OrderedSecond]] ![[OrderedFirst]]",
  "![[OrderedSecond]]",
  "![[OrderedFirst]]",
  "After ordered embeds",
  "",
  "Local block text ^local",
  "![[#^local]]",
})

write_file(root .. "/MainNoLocal.md", {
  "Plain before",
  "![[Target#Section]]",
  "![[Target#^block]]",
  "Plain after",
  "Not an embed yet",
})

write_file(root .. "/MainCache.md", {
  "![[CacheOuter]]",
  "![[CacheOuter]]",
})

write_file(root .. "/MainError.md", {
  "![[Explode]]",
  "![[ErrorAfter]]",
})

write_file(root .. "/ErrorAfter.md", {
  "after error body",
})

write_file(root .. "/MainManualCreate.md", {
  "![[CreatedLater]]",
})

vim.fn.mkdir(root .. "/RelativeMissing", "p")
write_file(root .. "/RelativeMissing/Main.md", {
  "![[./Later]]",
})

require("obsidian").setup {
  legacy_commands = false,
  workspaces = {
    {
      name = "smoke",
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

vim.cmd.edit(root .. "/Main.md")
local bufnr = vim.api.nvim_get_current_buf()
vim.b[bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local embeds = require("tom.obsidian_embeds")
embeds.setup {
  max_depth = 3,
  debounce_ms = 10,
  priority = 111,
  virt_lines_overflow = "scroll",
  virt_lines_leftcol = true,
  set_conceallevel = true,
}
embeds.attach(bufnr)
embeds.refresh(bufnr)
assert_true(vim.wo.conceallevel == 2, "attach should set conceallevel when configured")

local ns = vim.api.nvim_create_namespace(embeds.namespace)
local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })

-- Scenario: collect rendered virtual lines and their source-row ownership.
local rendered = {}
local rendered_chunks = {}
local rendered_by_row = {}
local rendered_chunk_lines_by_row = {}
local rendered_overlay_by_row = {}
local image_row
local block_row
local local_block_row
local aliased_heading_row
local nested_heading_row
local target_row
local section_row
local nested_row
local relative_nested_row
local trimmed_row
local alias_note_row
local plain_alias_row
local multi_embed_row
local ordered_anchor_row
local local_block_definition_row

for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
  if line == "![[Target]]" then
    target_row = row - 1
  elseif line == "![[Target#Section]]" then
    section_row = row - 1
  elseif line == "![[image.png]]" then
    image_row = row - 1
  elseif line == "![[Target#6|Verse 6 Alias]]" then
    aliased_heading_row = row - 1
  elseif line == "![[Target#Section#6|Nested Verse Alias]]" then
    nested_heading_row = row - 1
  elseif line == "![[Target#^block]]" then
    block_row = row - 1
  elseif line == "![[Nested]]" then
    nested_row = row - 1
  elseif line == "![[Outer/Parent]]" then
    relative_nested_row = row - 1
  elseif line == "![[Trimmed]]" then
    trimmed_row = row - 1
  elseif line == "![[AliasNote|Display Alias]]" then
    alias_note_row = row - 1
  elseif line == "![[PlainAlias|Ignored Alias]]" then
    plain_alias_row = row - 1
  elseif line == "![[OrderedSecond]] ![[OrderedFirst]]" then
    multi_embed_row = row - 1
  elseif line == "After ordered embeds" then
    ordered_anchor_row = row - 1
  elseif line == "![[#^local]]" then
    local_block_row = row - 1
  elseif line == "Local block text ^local" then
    local_block_definition_row = row - 1
  end
end

local function append_rendered_line(row, chunks, overlay)
  local rendered_line = {}
  for _, chunk in ipairs(chunks) do
    rendered_line[#rendered_line + 1] = chunk[1]
    rendered_chunks[#rendered_chunks + 1] = chunk
  end
  local line_text = table.concat(rendered_line, "")
  rendered[#rendered + 1] = line_text
  rendered_by_row[row][#rendered_by_row[row] + 1] = line_text
  rendered_chunk_lines_by_row[row][#rendered_chunk_lines_by_row[row] + 1] = chunks
  if overlay then
    rendered_overlay_by_row[row] = line_text
  end
end

local function collect_rendered(extmarks)
  rendered = {}
  rendered_chunks = {}
  rendered_by_row = {}
  rendered_chunk_lines_by_row = {}
  rendered_overlay_by_row = {}

  for _, mark in ipairs(extmarks) do
    local row = mark[2]
    local details = mark[4]
    rendered_by_row[row] = rendered_by_row[row] or {}
    rendered_chunk_lines_by_row[row] = rendered_chunk_lines_by_row[row] or {}
    if details.virt_text then
      append_rendered_line(row, details.virt_text, true)
    end
    for _, virt_line in ipairs(details.virt_lines or {}) do
      append_rendered_line(row, virt_line, false)
    end
  end
end

collect_rendered(marks)

local function assert_chunk(text, hl_group, message)
  for _, chunk in ipairs(rendered_chunks) do
    if chunk[1]:find(text, 1, true) and chunk[2] == hl_group then
      return
    end
  end
  fail(message .. "\nexpected highlighted chunk: " .. text .. " @ " .. hl_group)
end

local function has_conceal_on_row(extmarks, row)
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.conceal == "" then
      return true
    end
  end
  return false
end

local function has_conceal_lines_on_row(extmarks, row)
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.conceal_lines == "" then
      return true
    end
  end
  return false
end

local function overlay_text_on_row(extmarks, row)
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.virt_text then
      local parts = {}
      for _, chunk in ipairs(details.virt_text) do
        parts[#parts + 1] = chunk[1]
      end
      return table.concat(parts, "")
    end
  end
  return nil
end

local function has_virt_lines_above_with_text(extmarks, row, text)
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.virt_lines_above then
      for _, virt_line in ipairs(details.virt_lines or {}) do
        local parts = {}
        for _, chunk in ipairs(virt_line) do
          parts[#parts + 1] = chunk[1]
        end
        if table.concat(parts, ""):find(text, 1, true) then
          return true
        end
      end
    end
  end
  return false
end

local function virt_lines_above_text_on_row(extmarks, row)
  local lines = {}
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.virt_lines_above then
      for _, virt_line in ipairs(details.virt_lines or {}) do
        local parts = {}
        for _, chunk in ipairs(virt_line) do
          parts[#parts + 1] = chunk[1]
        end
        lines[#lines + 1] = table.concat(parts, "")
      end
    end
  end
  return table.concat(lines, "\n")
end

local function assert_extmark_display_options(extmarks)
  local saw_virt_lines = false
  local saw_conceal = false
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details.virt_lines then
      saw_virt_lines = true
      assert_true(details.priority == 111, "virt_lines extmark should use configured priority")
      assert_true(details.virt_lines_overflow == "scroll", "virt_lines extmark should use configured overflow")
      assert_true(details.virt_lines_leftcol == true, "virt_lines extmark should use configured leftcol setting")
    end
    if details.conceal == "" or details.conceal_lines == "" then
      saw_conceal = true
    end
  end
  assert_true(saw_virt_lines, "expected at least one rendered virt_lines extmark")
  assert_true(saw_conceal, "expected at least one conceal extmark")
end

local function source_render_text(extmarks, row)
  local lines = {}
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if mark[2] == row and details.virt_lines and not details.virt_lines_above then
      for _, virt_line in ipairs(details.virt_lines) do
        local parts = {}
        for _, chunk in ipairs(virt_line) do
          parts[#parts + 1] = chunk[1]
        end
        lines[#lines + 1] = table.concat(parts, "")
      end
    end
  end
  return table.concat(lines, "\n")
end

local function marks_with_cursor_on_buf(buffer, row)
  if vim.api.nvim_get_current_buf() ~= buffer then
    vim.api.nvim_win_set_buf(0, buffer)
  end
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd("doautocmd <nomodeline> CursorMoved")
  return vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true })
end

local function marks_with_cursor_on(row)
  return marks_with_cursor_on_buf(bufnr, row)
end

local function assert_nested_heading_marker()
  for _, row_lines in pairs(rendered_chunk_lines_by_row) do
    for _, virt_line in ipairs(row_lines) do
      local has_marker = false
      local has_heading = false
      for _, chunk in ipairs(virt_line) do
        if chunk[1] == "> " and chunk[2] == "@markup.quote" then
          has_marker = true
        elseif chunk[1]:find("## Section", 1, true) and chunk[2] == "@markup.heading.2" then
          has_heading = true
        end
      end
      if has_marker and has_heading then
        return
      end
    end
  end
  fail("nested embed should render a quote marker while preserving heading highlight")
end

assert_extmark_display_options(marks)
local rendered_text = table.concat(rendered, "\n")

-- Scenario: whole-note, heading, block, nested, and same-note embeds render
-- the same note slices Obsidian would expose, with frontmatter hidden by default.
assert_contains(rendered_text, "Intro line", "whole-note embed did not render body")
assert_true(not rendered_text:find("id: target", 1, true), "frontmatter should be hidden")
assert_contains(rendered_text, "## Section", "heading embed did not include heading")
assert_contains(rendered_text, "Section line", "heading embed did not include content")
assert_contains(rendered_text, "###### 6", "level-six heading embed did not include heading")
assert_contains(rendered_text, "Level six verse", "level-six heading embed did not include content")
assert_chunk("## Section", "@markup.heading.2", "heading was not highlighted with Tree-sitter")
assert_chunk("###### Verse 6 Alias", "@markup.heading.6", "aliased level-six heading was not highlighted with Tree-sitter")
local aliased_heading_text = source_render_text(marks_with_cursor_on(aliased_heading_row), aliased_heading_row)
assert_contains(aliased_heading_text, "###### Verse 6 Alias", "heading alias did not replace rendered heading")
assert_true(not aliased_heading_text:find("###### 6", 1, true), "original heading should be replaced by alias in rendered heading")
local nested_heading_text = source_render_text(marks_with_cursor_on(nested_heading_row), nested_heading_row)
assert_contains(nested_heading_text, "###### Nested Verse Alias", "nested heading anchor should resolve through the full parent chain")
assert_contains(nested_heading_text, "Level six verse", "nested heading anchor should render the linked section content")
assert_chunk("wiki label", "@markup.link.label", "wiki link label was not highlighted with Tree-sitter")
assert_chunk("markdown label", "@markup.link.label", "markdown link label was not highlighted with Tree-sitter")
assert_chunk("Target.md", "@markup.link.url", "markdown link target was not highlighted with Tree-sitter")
assert_chunk("`code`", "@markup.raw", "inline code was not highlighted with Tree-sitter")
assert_chunk("**bold**", "@markup.strong", "bold text was not highlighted with Tree-sitter")
assert_contains(rendered_text, "Block paragraph", "block embed did not render paragraph")
local block_text = source_render_text(marks_with_cursor_on(block_row), block_row)
assert_true(not block_text:find("^block", 1, true), "block id should be stripped")
assert_contains(rendered_text, "Local block text", "same-note block embed did not render")
local local_block_text = source_render_text(marks_with_cursor_on(local_block_row), local_block_row)
assert_true(not local_block_text:find("^local", 1, true), "same-note block id should be stripped")
assert_contains(rendered_text, "before nested", "nested note did not render")
assert_nested_heading_marker()

-- Scenario: relative refs inside nested embeds resolve from the embedded note's
-- directory, not the original buffer's directory.
local relative_nested_text = source_render_text(marks_with_cursor_on(relative_nested_row), relative_nested_row)
assert_contains(relative_nested_text, "child relative body", "nested relative embed should resolve from embedded note directory")
assert_true(
  not relative_nested_text:find("Embed not found: ./NestedDir/Child", 1, true),
  "nested relative embed should not resolve from the outer note directory"
)
local trimmed_text = source_render_text(marks_with_cursor_on(trimmed_row), trimmed_row)
local trimmed_lines = vim.split(trimmed_text, "\n", { plain = true })
assert_true(trimmed_lines[1] == "Trim first", "leading blank lines should be trimmed from rendered embeds")
assert_true(trimmed_lines[#trimmed_lines] == "Trim last", "trailing blank lines should be trimmed from rendered embeds")
assert_true(trimmed_lines[2] == "", "internal blank lines should be preserved when trimming rendered embeds")

-- Scenario: embed aliases replace only the first rendered heading and never
-- mutate the source note on disk.
local alias_note_text = source_render_text(marks_with_cursor_on(alias_note_row), alias_note_row)
assert_contains(alias_note_text, "# Display Alias", "whole-note alias should replace an initial heading")
assert_contains(alias_note_text, "Alias body remains", "whole-note alias should preserve body content")
assert_contains(alias_note_text, "## Child Heading", "whole-note alias should only replace the first heading")
assert_true(not alias_note_text:find("# Original Heading", 1, true), "original heading should be replaced by whole-note alias")
local alias_note_file = table.concat(vim.fn.readfile(root .. "/AliasNote.md"), "\n")
assert_contains(alias_note_file, "# Original Heading", "whole-note alias should not modify note contents")
local plain_alias_text = source_render_text(marks_with_cursor_on(plain_alias_row), plain_alias_row)
assert_contains(plain_alias_text, "Plain first line", "whole-note alias should not alter non-heading note bodies")
assert_true(not plain_alias_text:find("Ignored Alias", 1, true), "whole-note alias should only apply to initial headings")

-- Scenario: render order follows source order for same-line embeds and for
-- consecutive exact embed lines that are grouped into one concealed run.
local multi_embed_lines = vim.split(source_render_text(marks_with_cursor_on(multi_embed_row), multi_embed_row), "\n", { plain = true })
assert_true(
  multi_embed_lines[1] == "second ordered body",
  "first same-line embed should render first: " .. table.concat(multi_embed_lines, " | ")
)
assert_true(
  multi_embed_lines[2] == "first ordered body",
  "second same-line embed should render second: " .. table.concat(multi_embed_lines, " | ")
)
local consecutive_embed_lines = vim.split(virt_lines_above_text_on_row(marks, ordered_anchor_row), "\n", { plain = true })
assert_true(
  consecutive_embed_lines[1] == "second ordered body",
  "first consecutive embed line should render first: " .. table.concat(consecutive_embed_lines, " | ")
)
assert_true(
  consecutive_embed_lines[2] == "first ordered body",
  "second consecutive embed line should render second: " .. table.concat(consecutive_embed_lines, " | ")
)
assert_contains(rendered_text, "Embed not found: Missing", "missing embed warning did not render")
assert_contains(rendered_text, "Embed skipped: recursion limit reached", "recursive embed guard did not render")

-- Scenario: image/attachment embeds are ignored by this note renderer.
assert_true(not has_conceal_on_row(marks, image_row), "image embed should not get source conceal")
assert_true(not has_conceal_lines_on_row(marks, image_row), "image embed should not get line conceal")
assert_true(source_render_text(marks, image_row) == "", "image embed should not get rendered note lines")

-- Scenario: source conceal is cursor-sensitive. The current source line remains
-- visible, while exact embed lines away from the cursor are line-concealed.
marks = marks_with_cursor_on(target_row)
assert_true(not has_conceal_on_row(marks, target_row), "source link should remain visible on the cursor line")
assert_true(not has_conceal_lines_on_row(marks, target_row), "source line should remain visible on the cursor line")
assert_true(has_conceal_lines_on_row(marks, section_row), "standalone source line should be concealed away from the cursor line")
assert_true(overlay_text_on_row(marks, section_row) == nil, "hidden standalone source should use line conceal instead of overlay text")
assert_true(
  has_virt_lines_above_with_text(marks, image_row, "## Section"),
  "line-concealed embed should render above the next visible row: " .. virt_lines_above_text_on_row(marks, image_row)
)
local render_ref = embeds.render_ref
local render_ref_calls = 0
embeds.render_ref = function(...)
  render_ref_calls = render_ref_calls + 1
  return render_ref(...)
end
vim.api.nvim_win_set_cursor(0, { section_row + 1, 0 })
vim.cmd("doautocmd <nomodeline> CursorMoved")
embeds.render_ref = render_ref
local moved_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
assert_true(render_ref_calls == 0, "cursor movement should update cached extmarks without re-rendering embeds")
assert_true(has_conceal_lines_on_row(moved_marks, target_row), "source line should be concealed after the cursor leaves it")
assert_true(not has_conceal_on_row(moved_marks, section_row), "source link should be revealed after the cursor moves to its line")
assert_true(not has_conceal_lines_on_row(moved_marks, section_row), "source line should be revealed after the cursor moves to it")
assert_true(has_virt_lines_above_with_text(moved_marks, section_row, "Intro line"), "newly hidden source should render above the next visible row")
assert_contains(source_render_text(moved_marks, section_row), "## Section", "newly visible source should render below the source line")

-- Scenario: incremental refresh rerenders only changed embed rows when the edit
-- does not alter line count or same-note structure.
vim.cmd.edit(root .. "/MainNoLocal.md")
local no_local_bufnr = vim.api.nvim_get_current_buf()
vim.b[no_local_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
embeds.attach(no_local_bufnr)
embeds.refresh(no_local_bufnr)

local no_local_section_row
local no_local_block_row
local no_local_plain_row
local no_local_new_embed_row
for row, line in ipairs(vim.api.nvim_buf_get_lines(no_local_bufnr, 0, -1, false)) do
  if line == "![[Target#Section]]" then
    no_local_section_row = row - 1
  elseif line == "![[Target#^block]]" then
    no_local_block_row = row - 1
  elseif line == "Plain before" then
    no_local_plain_row = row - 1
  elseif line == "Not an embed yet" then
    no_local_new_embed_row = row - 1
  end
end

local no_local_block_text = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_block_row), no_local_block_row)
render_ref = embeds.render_ref
render_ref_calls = 0
embeds.render_ref = function(...)
  render_ref_calls = render_ref_calls + 1
  return render_ref(...)
end
vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_plain_row, no_local_plain_row + 1, false, { "Plain before changed" })
embeds.refresh_changed(no_local_bufnr)
embeds.render_ref = render_ref
assert_true(render_ref_calls == 0, "plain same-line edit without same-note refs should not re-render embeds")

render_ref = embeds.render_ref
render_ref_calls = 0
embeds.render_ref = function(...)
  render_ref_calls = render_ref_calls + 1
  return render_ref(...)
end
vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_section_row, no_local_section_row + 1, false, { "![[Target#6|Incremental Alias]]" })
embeds.refresh_changed(no_local_bufnr)
embeds.render_ref = render_ref
assert_true(render_ref_calls > 0, "editing an embed source row should re-render that row")
local incremental_section_text = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_section_row), no_local_section_row)
assert_contains(incremental_section_text, "###### Incremental Alias", "incremental embed edit should update rendered output")
local no_local_block_text_after = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_block_row), no_local_block_row)
assert_true(no_local_block_text_after == no_local_block_text, "incremental embed edit should leave unrelated rendered rows intact")

vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_section_row, no_local_section_row + 1, false, { "No embed here now" })
embeds.refresh_changed(no_local_bufnr)
local removed_embed_marks = marks_with_cursor_on_buf(no_local_bufnr, no_local_section_row)
assert_true(source_render_text(removed_embed_marks, no_local_section_row) == "", "changing an embed row to plain text should remove rendered output")
assert_true(not has_conceal_on_row(removed_embed_marks, no_local_section_row), "changing an embed row to plain text should remove conceal marks")
assert_true(not has_conceal_lines_on_row(removed_embed_marks, no_local_section_row), "changing an embed row to plain text should remove line conceal marks")

vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_new_embed_row, no_local_new_embed_row + 1, false, { "![[Target#Section]]" })
embeds.refresh_changed(no_local_bufnr)
local added_embed_text = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_new_embed_row), no_local_new_embed_row)
assert_contains(added_embed_text, "## Section", "changing plain text to an embed should render the new embed")

vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_new_embed_row, no_local_new_embed_row + 1, false, { "![[Target#6|Attached Alias]]" })
local attached_refresh = vim.wait(1000, function()
  local text = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_new_embed_row), no_local_new_embed_row)
  return text:find("###### Attached Alias", 1, true) ~= nil
end, 20)
assert_true(attached_refresh, "nvim_buf_attach on_lines should refresh changed embed rows")
vim.api.nvim_buf_set_lines(no_local_bufnr, no_local_new_embed_row, no_local_new_embed_row + 1, false, { "![[Target#Section]]" })
embeds.refresh_changed(no_local_bufnr)

local refresh = embeds.refresh
local refresh_calls = 0
embeds.refresh = function(...)
  refresh_calls = refresh_calls + 1
  return refresh(...)
end
vim.api.nvim_win_set_buf(0, bufnr)
vim.api.nvim_buf_set_lines(bufnr, local_block_definition_row, local_block_definition_row + 1, false, { "Local block changed ^local" })
embeds.refresh_changed(bufnr)
embeds.refresh = refresh
assert_true(refresh_calls == 1, "editing same-note block content should fall back to a full refresh, got " .. refresh_calls)

-- Scenario: writing a rendered target note refreshes buffers that depend on it.
vim.cmd.edit(root .. "/Target.md")
local target_bufnr = vim.api.nvim_get_current_buf()
local target_lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
for idx, line in ipairs(target_lines) do
  if line == "Section line" then
    vim.api.nvim_buf_set_lines(target_bufnr, idx - 1, idx, false, { "Section line changed by dependency write" })
    break
  end
end
vim.cmd.write()
local dependency_refreshed = vim.wait(1000, function()
  local dep_text = source_render_text(marks_with_cursor_on_buf(no_local_bufnr, no_local_new_embed_row), no_local_new_embed_row)
  return dep_text:find("Section line changed by dependency write", 1, true) ~= nil
end, 20)
assert_true(dependency_refreshed, "writing a target note should refresh buffers that render it")

-- Scenario: render-cache hits still preserve nested dependency tracking.
vim.cmd.edit(root .. "/MainCache.md")
local cache_bufnr = vim.api.nvim_get_current_buf()
vim.b[cache_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
embeds.attach(cache_bufnr)
embeds.refresh(cache_bufnr)

vim.api.nvim_buf_set_lines(cache_bufnr, 0, 1, false, { "Cache embed removed" })
embeds.refresh_changed(cache_bufnr)

vim.cmd.edit(root .. "/CacheInner.md")
local cache_inner_bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(cache_inner_bufnr, 0, 1, false, { "cache inner changed by dependency write" })
vim.cmd.write()
local cached_nested_dependency_refreshed = vim.wait(1000, function()
  local dep_text = source_render_text(marks_with_cursor_on_buf(cache_bufnr, 1), 1)
  return dep_text:find("cache inner changed by dependency write", 1, true) ~= nil
end, 20)
assert_true(
  cached_nested_dependency_refreshed,
  "cached embeds should preserve nested dependencies after incremental row edits"
)

-- Scenario: a renderer failure in one embed becomes an inline warning and does
-- not stop later embeds in the same buffer.
vim.cmd.edit(root .. "/MainError.md")
local error_bufnr = vim.api.nvim_get_current_buf()
vim.b[error_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local original_render_ref = embeds.render_ref
embeds.render_ref = function(ref, ctx)
  if ref.target == "Explode" then
    error("synthetic renderer failure")
  end
  return original_render_ref(ref, ctx)
end
embeds.attach(error_bufnr)
embeds.refresh(error_bufnr)
embeds.render_ref = original_render_ref
local error_text = source_render_text(marks_with_cursor_on_buf(error_bufnr, 0), 0)
assert_contains(error_text, "synthetic renderer failure", "unexpected renderer failures should render inline")
local after_error_text = source_render_text(marks_with_cursor_on_buf(error_bufnr, 1), 1)
assert_contains(after_error_text, "after error body", "renderer failure in one embed should not stop later embeds")

-- Scenario: unresolved refs are indexed so creating the missing note refreshes
-- existing buffers automatically.
vim.cmd.edit(root .. "/MainManualCreate.md")
local manual_missing_bufnr = vim.api.nvim_get_current_buf()
vim.b[manual_missing_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
embeds.attach(manual_missing_bufnr)
embeds.refresh(manual_missing_bufnr)
local missing_text = source_render_text(marks_with_cursor_on_buf(manual_missing_bufnr, 0), 0)
assert_contains(missing_text, "Embed not found: CreatedLater", "missing embeds should render a warning")
vim.cmd.edit(root .. "/CreatedLater.md")
vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { "created later body" })
vim.cmd.write()
local recovered_automatically = vim.wait(1000, function()
  local recovered_text = source_render_text(marks_with_cursor_on_buf(manual_missing_bufnr, 0), 0)
  return recovered_text:find("created later body", 1, true) ~= nil
end, 20)
assert_true(recovered_automatically, "creating a missing target should refresh unresolved embeds")

vim.cmd.edit(root .. "/RelativeMissing/Main.md")
local relative_missing_bufnr = vim.api.nvim_get_current_buf()
vim.b[relative_missing_bufnr].obsidian_buffer = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
embeds.attach(relative_missing_bufnr)
embeds.refresh(relative_missing_bufnr)
local relative_missing_text = source_render_text(marks_with_cursor_on_buf(relative_missing_bufnr, 0), 0)
assert_contains(relative_missing_text, "Embed not found: ./Later", "missing relative embeds should render a warning")
assert_true(
  not relative_missing_text:find("Embed error", 1, true),
  "missing relative embeds should not raise while resolving"
)
vim.cmd.edit(root .. "/RelativeMissing/Later.md")
vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { "relative later body" })
vim.cmd.write()
local relative_recovered_automatically = vim.wait(1000, function()
  local recovered_text = source_render_text(marks_with_cursor_on_buf(relative_missing_bufnr, 0), 0)
  return recovered_text:find("relative later body", 1, true) ~= nil
end, 20)
assert_true(relative_recovered_automatically, "creating a missing relative target should refresh unresolved embeds")

-- Scenario: toggling embeds off clears every render/conceal extmark.
vim.api.nvim_win_set_buf(0, bufnr)
embeds.toggle(bufnr)
local after_toggle = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
assert_true(#after_toggle == 0, "toggle should clear embed extmarks")

print("obsidian embeds smoke test passed")
