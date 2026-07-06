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

local vault_sync_status = function()
  if vim.fn.executable('vault-sync-status') ~= 1 then
    vim.notify('vault-sync-status is not available on PATH', vim.log.levels.ERROR)
    return
  end

  vim.system({ 'vault-sync-status' }, { text = true }, function(result)
    vim.schedule(function()
      local lines = vim.split((result.stdout or '') .. (result.stderr or ''), '\n', { trimempty = true })
      if #lines == 0 then
        lines = { 'vault-sync-status produced no output' }
      end

      vim.cmd('botright new')
      local bufnr = vim.api.nvim_get_current_buf()
      vim.bo[bufnr].buftype = 'nofile'
      vim.bo[bufnr].bufhidden = 'wipe'
      vim.bo[bufnr].swapfile = false
      vim.bo[bufnr].filetype = 'text'
      vim.api.nvim_buf_set_name(bufnr, 'vault-sync-status-' .. bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false
    end)
  end)
end

-- Obsidian
return {
  {
    'obsidian-nvim/obsidian.nvim',
    lazy = true,
    ft = { 'markdown' },
    version = '*',
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    opts = {
      legacy_commands = false,
      -- Only one obsidian workspace :)
      workspaces = {
        {
          name = "personal",
          path = get_workspace,
        },
      },
      frontmatter = {
        enabled = true,
      },
      completion = {
        min_chars = 2,
      },
      -- Setup the picker.
      picker = {
        name = "telescope.nvim",
      },
      sync = {
        enabled = true,
        trigger = "manual",
        configs = { "core-plugin", "core-plugin-data" },
      },
      templates = {
        folder = "Extras/Templates",
      },
      -- Put new notes in the "Encounters" subdir.
      new_notes_location = "Encounters",
      -- Set attachments to the correct folder.
      attachments = {
        folder = "Extras/Attachments",
      },
      -- Make sure that daily notes are in the right spot.
      daily_notes = {
        folder = "Calendar/Daily",
        date_format = "%Y-%m-%d",
        template = "daily-template.md",
      },
    },
    keys = {
      { '<leader>vf', '<cmd>Obsidian quick_switch<cr>', desc = 'Find vault note' },
      { '<leader>vg', '<cmd>Obsidian search<cr>', desc = 'Grep vault notes' },
      { '<leader>vd', '<cmd>Obsidian today<cr>', desc = 'Today note' },
      { '<leader>vD', '<cmd>Obsidian dailies<cr>', desc = 'Daily notes' },
      { '<leader>vn', '<cmd>Obsidian new<cr>', desc = 'New vault note' },
      { '<leader>vb', '<cmd>Obsidian backlinks<cr>', desc = 'Vault backlinks' },
      { '<leader>vl', '<cmd>Obsidian links<cr>', desc = 'Vault note links' },
      { '<leader>vt', '<cmd>Obsidian tags<cr>', desc = 'Vault tags' },
      { '<leader>vT', '<cmd>Obsidian template<cr>', desc = 'Insert vault template' },
      { '<leader>vo', '<cmd>Obsidian open<cr>', desc = 'Open note in Obsidian' },
      { '<leader>vs', vault_sync_status, desc = 'Vault sync status' },
      { '<leader>vS', '<cmd>Obsidian sync<cr>', desc = 'Vault sync menu' },
    },
  },
}
