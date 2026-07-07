-- Headless Tree-sitter parser crash smoke test.
--
-- Usage:
--   ts-parser-smoke
--   ts-parser-smoke --help
--
-- Direct usage:
--   nvim --clean --headless -l ~/.config/nvim/scripts/treesitter-parser-smoke.lua
--
-- The script prints phase markers before every risky operation. If Neovim segfaults,
-- the last printed phase is the operation to investigate.

local samples = {
  bash = [=[
#!/usr/bin/env bash
set -euo pipefail
for path in "$@"; do
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
  fi
done
]=],
  json = [[
{
  "name": "parser-smoke",
  "enabled": true,
  "items": [1, 2, {"nested": null}]
}
]],
  lua = [[
local M = {}
function M.add(a, b)
  return a + b
end
return M
]],
  nix = [[
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.neovim
  ];
}
]],
  rust = [[
fn main() {
    let values = [1, 2, 3];
    for value in values {
        println!("{value}");
    }
}
  ]],
}

local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
local repo_dir = vim.fn.stdpath("cache") .. "/arborist/repos"
local wasm_cache_dir = vim.fn.stdpath("cache") .. "/arborist-wasm-smoke"
local arborist_lock = vim.fn.stdpath("data") .. "/arborist-lock.json"
local arborist_config = vim.fn.stdpath("config") .. "/lua/tom/plugin/tree-sitter.lua"
local parser_registry = vim.fn.stdpath("data") .. "/lazy/arborist.nvim/registry/parsers.toml"

local function eprint(message)
  io.stderr:write(message .. "\n")
  io.stderr:flush()
end

local function expand(path)
  if not path then return nil end
  return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

local function args_after_separator()
  local argv = vim.v.argv or {}
  local out = {}
  local after = false
  for _, item in ipairs(argv) do
    if after then
      out[#out + 1] = item
    elseif item == "--" then
      after = true
    end
  end
  return out
end

local function parse_args()
  local opts = {}

  local argv = args_after_separator()
  local i = 1
  while i <= #argv do
    local key = argv[i]
    if key == "--sequence" then
      i = i + 1
      opts.sequence = argv[i]
    elseif key == "--help" or key == "-h" then
      opts.help = true
    else
      error("unknown argument: " .. tostring(key))
    end
    i = i + 1
  end

  return opts
end

local function parse_sequence(sequence)
  local result = {}
  for item in sequence:gmatch("[^,]+") do
    local lang, path = item:match("^([^=]+)=(.+)$")
    if not lang or not path then error("bad --sequence item: " .. item) end
    result[#result + 1] = { lang = lang, path = expand(path) }
  end
  return result
end

local function print_help()
  print([[
Tree-sitter parser crash smoke test

Common command:
  ts-parser-smoke

Runs installed WASM parser smoke tests and prints TS_RECOMMEND lines for the
Arborist native parser blacklist.

Direct command:
  nvim --headless -l ~/.config/nvim/scripts/treesitter-parser-smoke.lua

Options:
  --help                  Show this help. Other arguments are internal.
]])
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function installed_langs(lock_path)
  local text = read_file(lock_path)
  if not text then return {} end

  local ok, data = pcall(vim.json.decode, text)
  if not ok then error("could not parse Arborist lock: " .. data) end

  local langs = vim.tbl_keys(data.parsers or {})
  table.sort(langs)
  return langs
end

local function runtime_parser_langs()
  local result = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("parser/*", true)) do
    local lang = vim.fn.fnamemodify(path, ":t:r")
    if lang ~= "" then result[#result + 1] = lang end
  end
  table.sort(result)
  return result
end

local function native_blacklist(config_path)
  local text = read_file(config_path)
  if not text then return {} end

  local block = text:match("local%s+native_parsers%s*=%s*{(.-)}")
  if not block then return {} end

  local result = {}
  for lang in block:gmatch("([%w_%-]+)%s*=%s*true") do
    result[#result + 1] = lang
  end
  table.sort(result)
  return result
end

local function set_from_list(list)
  local result = {}
  for _, item in ipairs(list) do result[item] = true end
  return result
end

local function sorted_keys(set)
  local result = vim.tbl_keys(set)
  table.sort(result)
  return result
end

local function list_or_dash(set)
  local items = sorted_keys(set)
  return #items > 0 and table.concat(items, ",") or "-"
end

local function installed_parser_context()
  local lock_langs = installed_langs(arborist_lock)
  local runtime_langs = runtime_parser_langs()
  local blacklist_langs = native_blacklist(arborist_config)
  local candidate_set = set_from_list(lock_langs)

  for _, lang in ipairs(runtime_langs) do candidate_set[lang] = true end
  for _, lang in ipairs(blacklist_langs) do candidate_set[lang] = true end

  return {
    lock_langs = lock_langs,
    runtime_langs = runtime_langs,
    blacklist_langs = blacklist_langs,
    blacklist = set_from_list(blacklist_langs),
    candidates = sorted_keys(candidate_set),
  }
end

local function file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

local function repo_name_from_url(url)
  return (url:gsub("/+$", ""):match("([^/]+)$"))
end

local function parse_toml_value(value)
  local string_value = value:match('^"(.*)"$')
  if string_value then return (string_value:gsub('\\"', '"'):gsub("\\\\", "\\")) end
  if value == "true" then return true end
  if value == "false" then return false end
  return nil
end

local registry_cache

local function registry_entries()
  if registry_cache then return registry_cache end

  local f = io.open(parser_registry, "r")
  if not f then
    registry_cache = {}
    return registry_cache
  end

  local current
  local entries = {}
  for line in f:lines() do
    local section = line:match("^%[([%w_]+)%]$")
    if section then
      current = section
      entries[current] = entries[current] or {}
    elseif current then
      local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
      if key and value then
        entries[current][key] = parse_toml_value(vim.trim(value))
      end
    end
  end
  f:close()

  for lang, info in pairs(entries) do
    if not info.url then entries[lang] = nil end
  end
  registry_cache = entries
  return registry_cache
end

local function registry_info(lang)
  return registry_entries()[lang]
end

local function cached_repo_for_info(info)
  local primary = repo_dir .. "/" .. repo_name_from_url(info.url)
  if vim.uv.fs_stat(primary) then return primary end
  if info.fallback_url then
    local fallback = repo_dir .. "/" .. repo_name_from_url(info.fallback_url)
    if vim.uv.fs_stat(fallback) then return fallback end
  end
  return primary
end

local function parser_info(lang)
  local info = registry_info(lang)
  if info then return info end

  local hyphenated = lang:gsub("_", "-")
  return {
    url = "https://github.com/tree-sitter-grammars/tree-sitter-" .. hyphenated,
    fallback_url = "https://github.com/tree-sitter/tree-sitter-" .. hyphenated,
  }
end

local function build_dir_for_lang(lang)
  local info = parser_info(lang)
  local repo = cached_repo_for_info(info)
  if not vim.uv.fs_stat(repo) then return nil, "missing repo " .. repo end

  local build_dir = info.location and (repo .. "/" .. info.location) or repo
  if not vim.uv.fs_stat(build_dir) then
    return nil, "missing parser location " .. build_dir
  end

  return build_dir
end

local function build_wasm(lang)
  local existing = parser_dir .. "/" .. lang .. ".wasm"
  if file_exists(existing) then return existing end

  local build_dir, err = build_dir_for_lang(lang)
  if not build_dir then return nil, err end

  vim.fn.mkdir(wasm_cache_dir, "p")
  local dest = wasm_cache_dir .. "/" .. lang .. ".wasm"
  local result = vim.system({ "tree-sitter", "build", "--wasm", "-o", dest }, {
    cwd = build_dir,
    text = true,
  }):wait()

  if result.code ~= 0 or not file_exists(dest) then
    local output = vim.trim((result.stderr or "") .. (result.stdout or ""))
    if #output > 200 then output = output:sub(1, 200) .. "..." end
    return nil, output ~= "" and output or ("tree-sitter build failed with code " .. tostring(result.code))
  end

  return dest
end

local function wasm_parsers_for_langs(langs)
  local result = {}
  local skipped = {}

  for _, lang in ipairs(langs) do
    local path, err = build_wasm(lang)
    if path then
      result[#result + 1] = { lang = lang, path = path }
    else
      skipped[#skipped + 1] = { lang = lang, reason = err or "unknown" }
    end
  end
  return result, skipped
end

local function phase(lang, path, name, fn)
  print(("TS_SMOKE lang=%s parser=%s phase=%s"):format(lang, path, name))
  io.stdout:flush()
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    eprint(("TS_SMOKE_ERROR lang=%s parser=%s phase=%s\n%s"):format(lang, path, name, err))
    os.exit(1)
  end
end

local function exercise_parser(item)
  local lang = item.lang
  local path = item.path
  local text = samples[lang] or ("local parser_smoke_" .. lang .. " = true\n")

  phase(lang, path, "language.add", function()
    local ok = vim.treesitter.language.add(lang, { path = path })
    assert(ok == true, "vim.treesitter.language.add returned " .. vim.inspect(ok))
  end)

  local buf
  local parser

  phase(lang, path, "buffer.create", function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = lang
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.api.nvim_set_current_buf(buf)
  end)

  phase(lang, path, "parser.create", function()
    parser = vim.treesitter.get_parser(buf, lang, {})
  end)

  phase(lang, path, "parse.initial", function()
    local trees = parser:parse()
    assert(type(trees) == "table" and #trees > 0, "parser returned no trees")
  end)

  phase(lang, path, "highlight.start", function()
    vim.treesitter.start(buf, lang)
    vim.cmd("redraw")
  end)

  phase(lang, path, "edit.reparse", function()
    vim.api.nvim_win_call(0, function()
      vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "-- parser smoke edit" })
      parser:parse()
    end)
  end)

  phase(lang, path, "stop.delete.gc", function()
    pcall(vim.treesitter.stop, buf)
    parser = nil
    vim.api.nvim_buf_delete(buf, { force = true })
    for _ = 1, 10 do
      collectgarbage("collect")
    end
  end)
end

local function parser_ext(path)
  return vim.fn.fnamemodify(path, ":e")
end

local function parser_runtime_for(files)
  local dir = vim.fn.tempname()
  local parser_dir = dir .. "/parser"
  vim.fn.mkdir(parser_dir, "p")

  for _, item in ipairs(files) do
    local dest = ("%s/%s.%s"):format(parser_dir, item.lang, parser_ext(item.path))
    local ok, err = vim.uv.fs_symlink(item.path, dest)
    if not ok then
      ok, err = vim.uv.fs_copyfile(item.path, dest)
      assert(ok, ("could not stage parser for checkhealth: %s"):format(err or dest))
    end
  end

  return dir
end

local function run_treesitter_health(files)
  local runtime_dir = parser_runtime_for(files)

  phase("all", runtime_dir, "checkhealth", function()
    vim.opt.runtimepath:prepend(runtime_dir)
    vim.cmd("checkhealth vim.treesitter")
  end)
end

local function has_wasm_parser(files)
  for _, item in ipairs(files) do
    if parser_ext(item.path) == "wasm" then return true end
  end
  return false
end

local function last_phase(output)
  local last
  for line in output:gmatch("[^\r\n]+") do
    local phase_name = line:match("TS_SMOKE.-phase=([^%s]+)")
    if phase_name then last = phase_name:gsub("TS_SMOKE.*$", "") end
  end
  return last or "none"
end

local function run_child(script_path, sequence)
  local args = {
    vim.v.progpath,
    "--clean",
    "--headless",
    "-l",
    script_path,
    "--",
    "--sequence",
    sequence,
  }

  local result = vim.system(args, { text = true }):wait()
  local output = (result.stdout or "") .. (result.stderr or "")
  return result.code or 0, result.signal or 0, output
end

local function classify_child(code, signal, output)
  if signal ~= 0 then return "CRASH" end
  if output:find("TS_SMOKE ok", 1, true) and code == 0 then return "OK" end
  if output:find("TS_SMOKE_ERROR", 1, true) then return "FAIL" end
  if output:find("TS_SMOKE", 1, true) then return "CRASH" end
  if code == 0 then return "FAIL" end
  return code == 139 and "CRASH" or "FAIL"
end

local function parser_spec(parser)
  return ("%s=%s"):format(parser.lang, parser.path)
end

local function record_child_status(result, status, parser)
  if status == "OK" then return end
  if status == "CRASH" then result.crashes = result.crashes + 1 end
  if status == "FAIL" then result.failures = result.failures + 1 end
  result.unsafe[parser.lang] = true
end

local function run_parser_case(result, label, parser, script_path)
  local code, signal, output = run_child(script_path, parser_spec(parser))
  local status = classify_child(code, signal, output)
  record_child_status(result, status, parser)
  print(("TS_%s single=%s status=%s code=%d signal=%d last_phase=%s"):format(
    label,
    parser.lang,
    status,
    code,
    signal,
    last_phase(output)
  ))
  io.stdout:flush()
  return status
end

local function run_singles_for_parsers(label, parsers)
  local script_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
  local result = {
    crashes = 0,
    failures = 0,
    unsafe = {},
    single_status = {},
  }

  for _, parser in ipairs(parsers) do
    result.single_status[parser.lang] = run_parser_case(
      result,
      label,
      parser,
      script_path
    )
  end

  return result
end

local function print_matrix_inputs(context, wasm_parsers, wasm_skipped)
  print(("TS_MATRIX installed=%d runtime=%d blacklist=%d wasm=%d"):format(
    #context.lock_langs,
    #context.runtime_langs,
    #context.blacklist_langs,
    #wasm_parsers
  ))
  print(("TS_MATRIX config=%s"):format(arborist_config))
  for _, lang in ipairs(context.lock_langs) do
    print(("TS_MATRIX arborist_installed lang=%s"):format(lang))
  end
  for _, lang in ipairs(context.runtime_langs) do
    print(("TS_MATRIX runtime_installed lang=%s"):format(lang))
  end
  for _, lang in ipairs(context.blacklist_langs) do
    print(("TS_MATRIX blacklisted lang=%s"):format(lang))
  end
  for _, item in ipairs(wasm_parsers) do
    print(("TS_MATRIX parser lang=%s wasm=%s"):format(item.lang, item.path))
  end
  for _, item in ipairs(wasm_skipped) do
    print(("TS_MATRIX wasm_skip lang=%s reason=%s"):format(item.lang, item.reason:gsub("\n", " ")))
  end
  io.stdout:flush()
end

local function matrix_recommendations(context, wasm_parsers, wasm_skipped, wasm_result)
  local tested = set_from_list(vim.tbl_map(function(parser)
    return parser.lang
  end, wasm_parsers))
  local add = {}
  local remove = {}
  local keep = {}
  local untested = {}

  for lang in pairs(wasm_result.unsafe) do
    if not context.blacklist[lang] then add[lang] = true end
  end

  for lang in pairs(context.blacklist) do
    if not tested[lang] then
      untested[lang] = true
      keep[lang] = true
    elseif wasm_result.unsafe[lang] or wasm_result.single_status[lang] ~= "OK" then
      keep[lang] = true
    else
      remove[lang] = true
    end
  end

  return {
    add = add,
    remove = remove,
    keep = keep,
    untested = untested,
    skipped = vim.tbl_map(function(item)
      return item.lang .. ":" .. item.reason:gsub("%s+", "_")
    end, wasm_skipped),
  }
end

local function print_recommendations(recommendations)
  print(("TS_RECOMMEND add_to_blacklist=%s"):format(list_or_dash(recommendations.add)))
  print(("TS_RECOMMEND remove_from_blacklist=%s"):format(list_or_dash(recommendations.remove)))
  print(("TS_RECOMMEND keep_blacklisted=%s"):format(list_or_dash(recommendations.keep)))
  print(("TS_RECOMMEND untested_blacklisted=%s"):format(list_or_dash(recommendations.untested)))
  print(("TS_RECOMMEND skipped=%s"):format(table.concat(recommendations.skipped, ",")))
end

local function finish_matrix(wasm_result, tested_wasm)
  print(("TS_MATRIX done wasm_crashes=%d wasm_failures=%d"):format(
    wasm_result.crashes,
    wasm_result.failures
  ))
  if wasm_result.crashes > 0 then os.exit(139) end
  if wasm_result.failures > 0 then os.exit(1) end
  if not tested_wasm then
    eprint("No WASM parser artifacts to test.")
    os.exit(2)
  end
end

local function run_installed_matrix()
  local context = installed_parser_context()
  local wasm_parsers, wasm_skipped = wasm_parsers_for_langs(context.candidates)

  print_matrix_inputs(context, wasm_parsers, wasm_skipped)

  local wasm_result = run_singles_for_parsers("WASM", wasm_parsers)
  local recommendations = matrix_recommendations(context, wasm_parsers, wasm_skipped, wasm_result)

  print_recommendations(recommendations)
  finish_matrix(wasm_result, #wasm_parsers > 0)
end

local function run_sequence_smoke(opts)
  local files = parse_sequence(opts.sequence)
  if #files == 0 then
    eprint("No parser files found in --sequence.")
    os.exit(2)
  end

  print(("TS_SMOKE nvim=%s"):format(vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch))
  if has_wasm_parser(files) then
    run_treesitter_health(files)
  end
  for _, item in ipairs(files) do
    exercise_parser(item)
  end
  print("TS_SMOKE ok")
end

local function main()
  local opts = parse_args()
  if opts.help then
    print_help()
    return
  end

  if opts.sequence then
    run_sequence_smoke(opts)
    return
  end

  run_installed_matrix()
end

main()
