vim.opt_local.linebreak = true
vim.opt_local.tabstop = 2
vim.opt_local.softtabstop = 2
vim.opt_local.shiftwidth = 2

if vim.fn.expand("%:e") == "base" and pcall(require, "obsidian-base") then
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua.require'obsidian-base'.foldexpr(v:lnum, 1)"
  vim.wo.foldlevel = 99
end
