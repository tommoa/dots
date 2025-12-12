local dap = require('dap')

-- LLDB DAP adapter for macOS (and Linux if preferred over GDB)
-- See https://lldb.llvm.org/use/debugging.html
dap.adapters.lldb = {
    id = 'lldb',
    type = 'executable',
    command = 'lldb-dap',
}

dap.configurations.c = dap.configurations.c or {}
dap.configurations.cpp = dap.configurations.cpp or {}
dap.configurations.rust = dap.configurations.rust or {}
dap.configurations.zig = dap.configurations.zig or {}

local lldb_configs = {
    {
        name = 'Run executable (LLDB)',
        type = 'lldb',
        request = 'launch',
        program = function()
            local path = vim.fn.input({
                prompt = 'Path to executable: ',
                default = vim.fn.getcwd() .. '/',
                completion = 'file',
            })
            return (path and path ~= '') and path or dap.ABORT
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
    },
    {
        name = 'Run executable with arguments (LLDB)',
        type = 'lldb',
        request = 'launch',
        program = function()
            local path = vim.fn.input({
                prompt = 'Path to executable: ',
                default = vim.fn.getcwd() .. '/',
                completion = 'file',
            })
            return (path and path ~= '') and path or dap.ABORT
        end,
        args = function()
            local args_str = vim.fn.input({
                prompt = 'Arguments: ',
            })
            return vim.split(args_str, ' +')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
    },
    {
        name = 'Attach to process (LLDB)',
        type = 'lldb',
        request = 'attach',
        pid = require('dap.utils').pick_process,
    },
}

-- Add LLDB configurations to each language
for _, config in ipairs(lldb_configs) do
    table.insert(dap.configurations.c, config)
    table.insert(dap.configurations.cpp, config)
    table.insert(dap.configurations.rust, config)
    table.insert(dap.configurations.zig, config)
end
