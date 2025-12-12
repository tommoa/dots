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
            format = {
                enable = true,
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
    settings = {
        nixd = {
            formatting = {
                command = { "nixfmt" },
            },
        },
    },
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
-- Typescript
M.configs['ts_ls'] = {
    on_attach = on_attach,
    capabilities = capabilities
}
-- Zig
M.configs['zls'] = {
    on_attach = on_attach,
    capabilities = capabilities,
}

-- VHDL
M.configs['vhdl_ls'] = {
    on_attach = on_attach,
    capabilities = capabilities,
}

local ai_lsp_path = vim.uv.os_homedir() .. '/docs/ai-lsp/src/index.ts'
if (vim.uv or vim.loop).fs_stat(ai_lsp_path) then
    -- My own LSP check
    M.configs['ai-lsp'] = {
        on_attach = on_attach,
        capabilities = capabilities,
        init_options = {
            -- providers = {
            --     google = {
            --         model = "gemini-flash-latest",
            --     },
            -- },
            model = "google-vertex/gemini-2.5-flash",
            -- model = "openrouter/google/gemini-2.5-flash",
            -- model = "openrouter/openai/gpt-4.1-mini",
            -- model = "openai/gpt-5-nano",
        },
        cmd = { 'bun', 'run', ai_lsp_path, '--stdio' },
    }
end

-- Rust will be setup by `rustaceanvim`

for server, config in pairs(M.configs) do
    vim.lsp.config(server, config)
    vim.lsp.enable(server)
end

return M
