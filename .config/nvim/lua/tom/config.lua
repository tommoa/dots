local opt = vim.opt

opt.number = true         -- Turn on line numbers
opt.relativenumber = true -- Turn on relative numbers
opt.cursorline = true     -- Highlight the line we're on
opt.mouse = "a"           -- Allow interaction with the mouse
opt.hls = false           -- Don't highlight all matches in a search
opt.signcolumn = "yes"    -- Keep the gutter on the left open at all times
opt.scrolloff = 4         -- Keep 4 lines above and below the cursor
opt.bufhidden = "hide"    -- Let me hide buffers without unloading them
opt.conceallevel = 2      -- Hide some syntax things

-- Make sure that the CursorHold event is triggered faster than every 4 seconds (4000)
opt.updatetime = 300

-- Set tab/shiftwidth to 4 - as all civilised people should
opt.softtabstop = 4
opt.shiftwidth = 4
opt.tabstop = 4
opt.expandtab = true -- Use spaces for indentation by default

-- Make sure that spell checking is for Australian English
opt.spelllang = "en_au"

opt.shortmess:append "c"
opt.completeopt = "menuone,noselect,noinsert"

local has = function(x)
  return vim.fn.has(x) == 1
end
if has('termguicolors') then
    opt.termguicolors = true
end

-- Ensure that:
--  - Comments are italicised
--  - nvim displays italics properly. Sometimes it doesn't work if these are not set
vim.cmd [[
  filetype plugin indent on
  highlight Comment cterm=italic gui=italic
  set t_ZH="[3m"
  set t_ZR="[23m"
]]

-- Set the default shell
opt.shell = vim.env.SHELL

vim.g.markdown_fenced_languages = { 'html', 'python', 'bash=sh', 'rust', 'cpp' }

if vim.env.SSH_CLIENT ~= nil then
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
end

vim.fn.syntax = true
