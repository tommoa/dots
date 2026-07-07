-- Set the mapleader. This should be done first to make sure that it works in the rest of my keybindings
vim.g.mapleader = ","

require'tom.config'   -- Set some general options
require'tom.plugins'  -- Load plugins. This will also load my completion and LSP configs
require'tom.keybinds' -- Load some keybinds

-- Kick off machine-specific config files
local host = vim.uv.os_gethostname()
local config_dir = vim.fn.expand "~/.config/"
local filenames = {
    config_dir .. host .. '.vim',
    config_dir .. host .. '.lua',
    config_dir .. 'sysinit.vim',
    config_dir .. 'sysinit.lua',
}
for _, v in ipairs(filenames) do
    if vim.fn.filereadable(v) == 1 then
        vim.api.nvim_command('source ' .. v)
    end
end
