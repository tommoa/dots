local get_workspace = function()
  local os_name = vim.uv.os_uname().sysname
  local path = nil
  if os_name == "Darwin" then -- macOS
    path = vim.uv.os_homedir() .. "/Documents/Personal"
  elseif os_name == "Linux" then -- Linux
    path = vim.uv.os_homedir() .. "/docs/Personal"
  end
  if not vim.uv.fs_stat(path) then
    return assert(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
  end
  return path
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
      disable_frontmatter = true,
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
