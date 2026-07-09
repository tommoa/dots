---@return integer
local function current_buf()
  return vim.api.nvim_get_current_buf()
end

---@param data { fargs: string[] }
return function(data)
  local embeds = require("tom.obsidian_embeds")
  local subcommand = data.fargs[1] or "toggle"

  if subcommand == "toggle" then
    embeds.toggle(current_buf())
  elseif subcommand == "refresh" then
    embeds.refresh(current_buf())
  elseif subcommand == "stats" then
    vim.print(embeds.stats(current_buf()))
  else
    vim.notify("Usage: Obsidian embeds toggle|refresh|stats", vim.log.levels.ERROR)
  end
end
