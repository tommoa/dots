return {
  {
    'ravitemer/mcphub.nvim',
    event = 'VeryLazy',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    build = 'bundled_build.lua',   -- Installs `mcp-hub` node binary locally
    opts = {
      use_bundled_binary = true, -- Use local `mcp-hub` binary
      auto_approve = true,
      extensions = {
        avante = {
          make_slash_commands = false,
        },
      },
    },
  },
}
