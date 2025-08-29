local lspconfig = require('lspconfig')

local M = {}

local capabilities = vim.tbl_deep_extend(
    'force',
    vim.lsp.protocol.make_client_capabilities(),
    require('blink.cmp').get_lsp_capabilities()
)
M.capabilities = capabilities

local on_attach = function(client, bufnr)
    local opts = { buffer = bufnr, remap = false }

    -- See `:help vim.lsp.*` for documentation on any of the below functions
    vim.keymap.set('n', '<leader>d', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', '<leader>h', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, opts)
    vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<leader>r', vim.lsp.buf.rename, opts)
    vim.keymap.set('n', '<leader>a', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, opts)
    vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, opts)
    vim.keymap.set("n", "<leader>o", vim.lsp.buf.format, opts)
    -- Run formatting synchronously before writing a file
    vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = bufnr,
        callback = vim.lsp.buf.format,
    })
end
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

-- Rust will be setup by `rustaceanvim`

for server, config in pairs(M.configs) do
    lspconfig[server].setup(config)
    vim.lsp.config(server, config)
    vim.lsp.enable(server)
end

return M
