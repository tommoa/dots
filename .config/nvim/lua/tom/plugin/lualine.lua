return {
    {
        'nvim-lualine/lualine.nvim',
        event = 'VeryLazy', -- Allow lualine to come in late
        opts = {
            options = {
                section_separators = { left = '', right = '' },
                component_separators = { left = '', right = '|' },
                disabled_filetypes = {
                    'Avante',
                    'AvanteInput',
                    'AvanteOutput',
                    'AvanteSelectedFiles',
                    'AvanteTodos',
                },
            },
            sections = {
                lualine_a = { 'mode' },
                lualine_b = {
                    {
                        'diagnostics',
                        separator = '|',
                        update_in_insert = true,
                        icon = '',
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
                        icon = '',
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
                        icon = '(lsp)',
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
        },
    },
}
