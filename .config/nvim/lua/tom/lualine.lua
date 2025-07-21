local utils = require('lualine.utils.utils')
local mcphub_colors = {
    unloaded = { fg = utils.extract_highlight_colors("DiagnosticHint", "fg") },
    connected = { fg = utils.extract_highlight_colors("DiagnosticInfo", "fg") },
    connecting = { fg = utils.extract_highlight_colors("DiagnosticWarn", "fg") },
    error = { fg = utils.extract_highlight_colors("DiagnosticError", "fg") },
}

require('lualine').setup {
    options = {
        section_separators = { left = '', right = '' },
        component_separators = { left = '', right = '|' },
        disabled_filetypes = {
            'AvanteTodos',
            'AvanteSelectedFiles',
        },
    },
    extensions = {
        'avante',
    },
    sections = {
        lualine_a = { 'mode' },
        lualine_b = {
            {
                function()
                    -- Check if MCPHub is loaded
                    if not vim.g.loaded_mcphub then
                        return "-"
                    end

                    local count = vim.g.mcphub_servers_count or 0
                    local status = vim.g.mcphub_status or "stopped"
                    local executing = vim.g.mcphub_executing

                    -- Show "-" when stopped
                    if status == "stopped" then
                        return "-"
                    end

                    -- Show spinner when executing, starting, or restarting
                    if executing or status == "starting" or status == "restarting" then
                        local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
                        local frame = math.floor(vim.loop.now() / 100) % #frames + 1
                        return frames[frame]
                    end

                    return count
                end,
                color = function()
                    if not vim.g.loaded_mcphub then
                        return mcphub_colors.unloaded
                    end

                    local status = vim.g.mcphub_status or "stopped"
                    if status == "ready" or status == "restarted" then
                        return mcphub_colors.connected
                    elseif status == "starting" or status == "restarting" then
                        return mcphub_colors.connecting
                    else
                        return mcphub_colors.error
                    end
                end,
                padding = { left = 1, right = 0 },
                icon = '(mcp)',
            },
            {
                'diagnostics',
                separator = '|',
                update_in_insert = true,
                icon='',
                symbols = { error = 'E ', warn = 'W ', info = 'I ', hint = 'H ' },
                padding = { left = 1, right = 1 },
            },
            {
                'filename',
                path = 1,
                shorting_target = 85,
            },
        },
        lualine_c = {
            {
                'branch',
                icon='',
                color = { fg = 'grey', }
            },
            {
                -- Get the root directory of the current git repository.
                function()
                    local git_dir = require('lualine.components.branch.git_branch').find_git_dir()
                    if not git_dir then
                        return ''
                    end

                    local git_root = git_dir:gsub('/.git/?$', '')
                    return git_root:match '^.+/(.+)$'
                end,
            },
            {
                'diff',
                source = function()
                    local gitsigns = vim.b.gitsigns_status_dict
                    if gitsigns then
                        return {
                            added = gitsigns.added,
                            modified = gitsigns.changed,
                            removed = gitsigns.removed,
                        }
                    end
                end,
            },
            {
                'lsp_status',
                icon='(lsp)',
                padding = 0,
            },
        },
        lualine_x = {
            {
                "fileformat",
                icons_enabled = false,
            },
            "encoding",
            "filetype"
        },
    },
}
