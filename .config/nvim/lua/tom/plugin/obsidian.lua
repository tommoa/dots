local get_workspace = function()
  local os_name = vim.uv.os_uname().sysname
  if os_name == "Darwin" then -- macOS
    return "~/Documents/Personal"
  elseif os_name == "Linux" then -- Linux
    return "~/docs/Personal"
  else
    return nil
  end
end
  -- Obsidian
return {
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
        {
          name = "personal",
          path = get_workspace,
        },
      },
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
