return {
  {
    'arborist-ts/arborist.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    cmd = { 'Arborist', 'ArboristInstall', 'ArboristUpdate', 'ArboristClean' },
    config = function()
      local native_parsers = {
        bash = true,
        rust = true,
      }

      local function prefer_native_for_some_parsers()
        local compile = require('arborist.compile')
        if compile._tom_native_parser_wrapper then return end

        local original_build_wasm = compile.build_wasm

        compile.build_wasm = function(repo_path, info, dest, callback)
          local lang = dest:match('([^/]+)%.wasm$')
          if lang and native_parsers[lang] then
            callback('WASM disabled for ' .. lang)
            return
          end
          original_build_wasm(repo_path, info, dest, callback)
        end

        compile._tom_native_parser_wrapper = true
      end

      prefer_native_for_some_parsers()
      require('arborist').setup({
        install_popular = false,
        update_cadence = 'weekly',
      })
    end,
  },
}
