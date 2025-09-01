local mapper = function(mode, key, result)
  vim.api.nvim_set_keymap(mode, key, result, { noremap = true, silent = true })
end

-- Colemak problems
mapper("", "j", "e")
mapper("", "J", "E")
mapper("", "k", "n")
mapper("", "K", "N")
mapper("", "l", "u")
mapper("", "L", "U")
mapper("", "i", "l")
mapper("", "n", "gj")
mapper("", "e", "gk")
mapper("", "u", "i")
mapper("", "I", "L")
mapper("", "N", "J")
mapper("", "E", "K")
mapper("", "U", "I")
-- Normal-mode specific
mapper("n", "k", "nzzzv")
mapper("n", "K", "Nzzzv")
mapper("n", "<C-f>", "<C-f>zzzv")
mapper("n", "<C-b>", "<C-b>zzzv")
mapper("n", "<C-u>", "<C-u>zzzv")
mapper("n", "<C-d>", "<C-d>zzzv")
-- Moving between panes
mapper("n", "<left>", "<c-w>h")
mapper("n", "<right>", "<c-w>l")
mapper("n", "<down>", "<c-w>j")
mapper("n", "<up>", "<c-w>k")
mapper("", "<M-h>", "<c-w>h")
mapper("", "<M-n>", "<c-w>j")
mapper("", "<M-e>", "<c-w>k")
mapper("", "<M-i>", "<c-w>l")
-- Buffer-related keybinds
mapper("", "<M-u>", ":bn!<CR>")
mapper("", "<M-l>", ":bp!<CR>")
mapper("n", "zk", ":bd!<CR>")
mapper("n", "gV", "`[v`]")
-- When using the nvim terminal, escape puts you back in normal mode
mapper("t", "<Esc>", "<c-\\><c-n>")

-- LSP keybinds
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(e)
    local opts = { buffer = e.buf, remap = false }

    -- See `:help vim.lsp.*` for documentation on any of the below functions
    vim.keymap.set('n', '<leader>d', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', '<leader>h', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, opts)
    vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<leader>r', vim.lsp.buf.rename, opts)
    vim.keymap.set('n', '<leader>ga', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>n', vim.diagnostic.open_float, opts)
    vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, opts)
    vim.keymap.set("n", "<leader>o", vim.lsp.buf.format, opts)
    -- Run formatting synchronously before writing a file
    vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = e.buf,
        callback = vim.lsp.buf.format,
    })
  end
})

-- Keymaps for plugins.
--   telescope:
--     zf:         find_files
--     zb:         buffers
--     <leader>en  find neovim files
--   harpoon:
--     <leader>t   add to list
--     <leader>s   toggle menu
--     <C-n>       select 1
--     <C-e>       select 2
--     <C-t>       select 3
--     <C-s>       select 4
--   avante:
--     <leader>aC  AvanteClear
--     <leader>an  AvanteChatNew
