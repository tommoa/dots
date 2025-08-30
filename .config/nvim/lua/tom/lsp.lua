local lspconfig = require('lspconfig')

local M = {}

local capabilities = vim.tbl_deep_extend(
    'force',
    vim.lsp.protocol.make_client_capabilities(),
    require('blink.cmp').get_lsp_capabilities()
)
M.capabilities = capabilities

local on_attach = function(client, bufnr) end
M.on_attach = on_attach

M.configs = {}

-- Lua
M.configs['lua_ls'] = {
    settings = {
        Lua = {
            runtime = {
                version = 'LuaJIT'
            },
            diagnostics = {
                globals = {
                    'vim'
                }
            },
            workspace = {
                library = {
                    vim.api.nvim_get_runtime_file("", true),
                    "${3rd}/luv/library",
                },
            },
            telemetry = {
                enable = false
            }
        }
    },
    on_attach = on_attach,
    capabilities = capabilities
}
-- Clangd
M.configs['clangd'] = {
    init_options = {
        clangdFileStatus = true
    },
    on_attach = on_attach,
    capabilities = capabilities
}
-- Python
M.configs['pyright'] = {
    on_attach = on_attach,
    capabilities = capabilities,
}
-- Nix
M.configs['nixd'] = {
    on_attach = on_attach,
    capabilities = capabilities,
}
-- Markdown
M.configs['markdown_oxide'] = {
    on_attach = on_attach,
    capabilities = vim.tbl_deep_extend(
        'force',
        capabilities,
        { workspace = { didChangeWatchedFiles = { dynamicRegistration = true, }, }, }
    ),
}

-- Rust will be setup by `rustaceanvim`

for server, config in pairs(M.configs) do
    lspconfig[server].setup(config)
    vim.lsp.config(server, config)
    vim.lsp.enable(server)
end

return M
