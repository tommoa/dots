return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      {
        'mfussenegger/nvim-dap-python',
        lazy = true,
        config = function ()
          require('dap-python').setup('uv')
        end,
      },
      {
        'rcarriga/nvim-dap-ui',
        lazy = true,
        dependencies = {
          'nvim-neotest/nvim-nio',
        },
        opts = {
          controls = {
            enabled = false,
          },
          icons = {
            expanded = 'v',
            collapsed = '>',
            current_frame = '<',
          },
        },
        keys = {
          { "<leader>bt", function() require('dapui').toggle() end, desc = 'DAP: Toggle view' },
          { "<leader>bw", function() require('dapui').elements.watches.add(vim.fn.input('Expression to watch:')) end, desc = 'DAP: Add to watches' },
        },
      },
    },
    lazy = true,
    config = function ()
      local dap = require('dap')
      local ui = require('dapui')

      if vim.fn.executable('gdb') == 1 then
        require('tom.plugin.dap.gdb')
      end
      if vim.fn.executable('lldb-dap') == 1 then
        require('tom.plugin.dap.lldb')
      end
      dap.listeners.before.attach.dapui_config = function()
        ui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        ui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        ui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        ui.close()
      end
    end,
    keys = {
      { "<leader>gb", function() require('dap').run_to_cursor() end, desc = 'DAP: Run to cursor' },
      { "<leader>bb", function() require('dap').toggle_breakpoint() end, desc = 'DAP: Toggle breakpoint' },
      { '<leader>bc', function() require('dap').continue() end, desc = 'DAP: Continue' },
      { '<leader>bn', function() require('dap').step_over() end, desc = 'DAP: Step Over (next)' },
      { '<leader>be', function() require('dap').step_back() end, desc = 'DAP: Step Back (back)' },
      { '<leader>bi', function() require('dap').step_into() end, desc = 'DAP: Step Into (step)' },
      { '<leader>bh', function() require('dap').step_out() end, desc = 'DAP: Step Out (leave)' },
      { '<leader>bu', function() require('dap').up() end, desc = 'DAP: Up stack trace' },
      { '<leader>bd', function() require('dap').down() end, desc = 'DAP: Down stack trace' },
      { '<leader>br', function() require('dap').repl.toggle() end, desc = 'DAP: Toggle REPL' },
      { '<leader>bs', function() require('dap').terminate() end, desc = 'DAP: Toggle Session' },
    },
  }
}
