local parsers = {
  "bash",
  "c",
  "cpp",
  "python",
  "vim",
  "lua",
  "markdown",
  "markdown_inline",
  "rust",
  "nix",
  "css",
  "html",
  "gitcommit",
  "gitignore",
  "git_config",
  "git_rebase",
  "gitattributes",
}

return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    config = function()
      local treesitter = require('nvim-treesitter')
      treesitter.setup()

      local available_parsers

      local function enable_treesitter(buf)
        local ok = pcall(vim.treesitter.start, buf)
        if ok then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          return
        end

        local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype) or vim.bo[buf].filetype
        available_parsers = available_parsers or treesitter.get_available()
        if
          lang == ""
          or vim.list_contains(treesitter.get_installed('parsers'), lang)
          or not vim.list_contains(available_parsers, lang)
        then
          return
        end

        treesitter.install(lang):await(function()
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) and vim.list_contains(treesitter.get_installed('parsers'), lang) then
              enable_treesitter(buf)
            end
          end)
        end)
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('tom-treesitter', { clear = true }),
        callback = function(args)
          enable_treesitter(args.buf)
        end,
      })
    end,
    build = function()
      require('nvim-treesitter').install(parsers):pwait(300000)
    end,
  },
}
