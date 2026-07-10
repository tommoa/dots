return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        layout = {
          preset = 'ivy',
        },
        win = {
          input = {
            keys = {
              ['<Esc>'] = { 'close', mode = { 'n', 'i' } },
            },
          },
          list = {
            keys = {
              ['<Esc>'] = 'close',
            },
          },
          preview = {
            keys = {
              ['<Esc>'] = 'close',
            },
          },
        },
        icons = {
          files = {
            enabled = false,
          },
        },
      },
      image = {
        enabled = true,
        resolve = function(file, src)
          local ok, api = pcall(require, 'obsidian.api')
          if not ok then
            return
          end

          if api.path_is_note(file) then
            return api.resolve_attachment_path(src)
          end
        end,
      },
    },
    keys = {
      { 'zf', function() Snacks.picker.files() end, desc = 'Find files' },
      { 'zb', function() Snacks.picker.buffers() end, desc = 'List buffers' },
      { '<leader>ff', function() Snacks.picker.files() end, desc = 'Find files' },
      {
        '<leader>en',
        function()
          Snacks.picker.files({
            cwd = vim.fn.stdpath('config'),
            hidden = true,
            ignored = true,
          })
        end,
        desc = 'Find files in nvim config',
      },
      {
        '<leader>ec',
        function()
          Snacks.picker.files({
            cwd = vim.fn.expand('~/.config/nixpkgs'),
            hidden = true,
            ignored = true,
          })
        end,
        desc = 'Find files in nixpkgs config',
      },
    },
  },
}
