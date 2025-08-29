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
mapper("n", "<C-f>", "<C-u>zzzv")
mapper("n", "<C-b>", "<C-u>zzzv")
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

-- Add a keybind for finding files with Telescope
mapper("n", "zf", ":Telescope find_files<CR>")
mapper("n", "zb", ":Telescope buffers<CR>")

-- Clear Avante chat history
mapper("n", "<leader>aC", ":AvanteClear<CR>")
mapper("n", "<leader>an", ":AvanteChatNew<CR>")
