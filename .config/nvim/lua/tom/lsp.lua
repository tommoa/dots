local M = {}

local capabilities = vim.tbl_deep_extend(
    'force',
    vim.lsp.protocol.make_client_capabilities(),
    require('blink.cmp').get_lsp_capabilities()
)
vim.lsp.config('*', { capabilities = capabilities })

local preferred_formatters = {
    lua = 'lua_ls',
    nix = 'nixd',
}

local function format_client(bufnr)
    local formatters = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/formatting' })
    local preferred = preferred_formatters[vim.bo[bufnr].filetype]
    if preferred then
        for _, client in ipairs(formatters) do
            if client.name == preferred then
                return client
            end
        end
    end

    if #formatters == 1 then
        return formatters[1]
    end

    -- Require an explicit preference when several clients can format a buffer.
    if #formatters > 1 then
        local names = {}
        for _, client in ipairs(formatters) do
            table.insert(names, client.name)
        end
        table.sort(names)
        vim.notify_once(
            ('LSP formatting skipped for %s: multiple clients support formatting (%s)'):format(
                vim.bo[bufnr].filetype,
                table.concat(names, ', ')
            ),
            vim.log.levels.WARN
        )
    end
end

local function has_save_edit_client(bufnr)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client:supports_method('textDocument/willSaveWaitUntil', bufnr) then
            return true
        end
    end
    return false
end

local function format_buffer(bufnr, for_save)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    -- Neovim applies willSaveWaitUntil edits from every attached client during writes.
    if for_save and has_save_edit_client(bufnr) then
        return
    end

    local client = format_client(bufnr)
    if client then
        vim.lsp.buf.format({
            bufnr = bufnr,
            id = client.id,
            async = false,
        })
    end
end

function M.format(bufnr)
    format_buffer(bufnr, false)
end

local format_group = vim.api.nvim_create_augroup('tom.lsp.format', { clear = true })
vim.api.nvim_create_autocmd('BufWritePre', {
    group = format_group,
    desc = 'Format with the selected LSP client before saving',
    callback = function(args)
        -- Neovim handles willSaveWaitUntil clients as part of the write cycle.
        format_buffer(args.buf, true)
    end,
})

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
}
-- Clangd
M.configs['clangd'] = {
    init_options = {
        clangdFileStatus = true
    },
}
-- Elixir
M.configs['elixirls'] = {}
-- Python
M.configs['pyright'] = {}
-- Nix
M.configs['nixd'] = {
    settings = {
        nixd = {
            formatting = {
                command = { "alejandra" },
            },
        },
    },
}
-- Markdown
M.configs['markdown_oxide'] = {
    root_markers = { '.obsidian', '.moxide.toml', '.git' },
    capabilities = vim.tbl_deep_extend(
        'force',
        capabilities,
        { workspace = { didChangeWatchedFiles = { dynamicRegistration = true, }, }, }
    ),
}
-- Typescript
M.configs['ts_ls'] = {}
-- Zig
M.configs['zls'] = {}

local ai_lsp_path = vim.fs.joinpath(vim.uv.os_homedir(), 'docs', 'ai-lsp', 'src', 'index.ts')
if vim.uv.fs_stat(ai_lsp_path) then
    -- My own LSP check
    M.configs['ai-lsp'] = {
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
