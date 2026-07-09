local get_workspace = function()
  local os_name = vim.uv.os_uname().sysname
  local path = nil
  if os_name == "Darwin" then -- macOS
    path = vim.fs.joinpath(vim.uv.os_homedir(), "Documents", "Personal")
  elseif os_name == "Linux" then -- Linux
    path = vim.fs.joinpath(vim.uv.os_homedir(), "docs", "Personal")
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

local follow_obsidian_link_or_file = function()
  if require('obsidian.api').cursor_link() then
    require('obsidian.actions').follow_link()
  else
    vim.cmd('normal! gf')
  end
end

local notes_subdir = "Encounters"
local bible_sources_subdir = "Sources/Bible"
local pending_unique_note_title = nil

local is_in_subdir = function(path, subdir)
  local normalized = vim.fs.normalize(tostring(path), { expand_env = false })
  local normalized_subdir = vim.fs.normalize(subdir, { expand_env = false })
  return normalized == normalized_subdir or vim.startswith(normalized, normalized_subdir .. "/")
end

local title_id = function(title, dir)
  return require("obsidian.builtin").title_id(title, dir)
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
    config = function(_, opts)
      local obsidian = require('obsidian')
      obsidian.setup(opts)
      obsidian.register_command('embeds', {
        nargs = '*',
        note_action = true,
        complete = function(arg_lead)
          return vim.tbl_filter(function(item)
            return vim.startswith(item, arg_lead)
          end, { 'toggle', 'refresh', 'stats' })
        end,
      })
    end,
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
        enabled = function(path)
          return not is_in_subdir(path, bible_sources_subdir)
        end,
      },
      callbacks = {
        enter_note = function()
          vim.keymap.set('n', 'gf', follow_obsidian_link_or_file, {
            buffer = true,
            desc = 'Follow Obsidian link or file',
          })
          require('tom.obsidian_embeds').attach(0)
        end,
        create_note = function(note, opts)
          if opts.scope ~= "unique" then
            return
          end

          local title = pending_unique_note_title or note.title
          pending_unique_note_title = nil

          if title ~= nil and title ~= "" and title ~= note.id then
            note.title = title
            note:add_alias(title)
          end
        end,
      },
      completion = {
        min_chars = 2,
      },
      -- Setup the picker.
      picker = {
        name = "snacks.picker",
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
      notes_subdir = notes_subdir,
      new_notes_location = "notes_subdir",
      note_id_func = function(title, dir)
        return title_id(title, dir)
      end,
      unique_note = {
        folder = notes_subdir,
      },
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
