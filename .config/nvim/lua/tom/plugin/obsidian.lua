return {
  -- Obsidian
  {
    'epwalsh/obsidian.nvim',
    lazy = true,
    ft = { 'markdown' },
    version = '*',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      -- Only one obsidian workspace :)
      workspaces = {
        { -- This is my configuration for Linux.
          name = "personal",
          path = "~/docs/Personal",
        },
        { -- This is my configuration for macOS.
          name = "personal",
          path = "~/Documents/Personal",
        },
      },
      -- Setup completion.
      completion = {
        blink = true,
        min_chars = 2,
      },
      -- Setup the picker.
      picker = {
        name = "telescope.nvim",
      },
      -- Put new notes in the "Encounters" subdir.
      new_notes_location = "Encounters",
      -- Set attachments to the correct folder.
      attachments = {
        img_folder = "Extras/Attachments",
      },
      -- Make sure that daily notes are in the right spot.
      daily_notes = {
        folder = "Calendar/Daily",
        date_format = "%Y-%m-%d",
        template = "Extras/Templates/daily-template.md",
      },
    },
  },
}
