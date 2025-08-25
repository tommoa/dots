local configs = require('nvim-treesitter.configs')
local uname = vim.loop.os_uname()

configs.setup {
    ensure_installed = "all",
    ignore_install = {
        "ipkg",
        "norg",
    },
    auto_install = false,
    sync_install = false,
    modules= {},
    highlight = {
        -- Treesitter doesn't have 32-bit binaries
        enable = uname.machine ~= "i686",
        disable = {},
    },
}
