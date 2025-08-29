return {
  -- blink.cmp
  {
    'saghen/blink.cmp',
    version = "1.*",
    opts = {
      keymap = {
        preset = "super-tab",
      },
      completion = {
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 50,
        },
        ghost_text = {
          enabled = true,
        },
        menu = {
          draw = {
            treesitter = { 'lsp', },
            columns = {
              { 'kind' }, { 'label', 'label_description', gap = 1 },
            },
          },
        },
      },
      cmdline = {
        keymap = { preset = 'inherit' },
        completion = {
          menu = {
            auto_show = true
          },
        },
      },
    },
  }
}
