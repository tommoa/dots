local M = {}

---@param message string
function M.fail(message)
  error(message, 0)
end

---@param value any
---@param message string
function M.assert_true(value, message)
  if not value then
    M.fail(message)
  end
end

---@param haystack string
---@param needle string
---@param message string
function M.assert_contains(haystack, needle, message)
  if not haystack:find(needle, 1, true) then
    M.fail(message .. "\nexpected to find: " .. needle .. "\nin: " .. haystack)
  end
end

---@param path string
---@param lines string[]
function M.write_file(path, lines)
  local file = assert(io.open(path, "w"))
  file:write(table.concat(lines, "\n"))
  file:write("\n")
  file:close()
end

---@return nil
function M.setup_runtime()
  local config_dir = vim.fn.expand("~/.config/nvim")
  vim.opt.runtimepath:prepend(config_dir)

  local explicit = vim.env.OBSIDIAN_EMBEDS_RTP
  if explicit and explicit ~= "" then
    for _, path in ipairs(vim.split(explicit, ":", { plain = true, trimempty = true })) do
      vim.opt.runtimepath:prepend(path)
    end
    return
  end

  local lazy_dir = vim.fn.expand("~/.local/share/nvim/lazy")
  vim.opt.runtimepath:prepend(lazy_dir .. "/obsidian.nvim")
  vim.opt.runtimepath:prepend(lazy_dir .. "/plenary.nvim")
end

---@param bufnr integer
---@param namespace integer
---@return string
function M.rendered_text(bufnr, namespace)
  local lines = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
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

return M
