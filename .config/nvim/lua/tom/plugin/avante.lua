return {
  {
    'yetone/avante.nvim',
    event = 'InsertEnter',
    cmd = 'Avante',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'stevearc/dressing.nvim',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'ravitemer/mcphub.nvim',
    },
    build = 'make',
    branch = 'main',
    opts = {
      -- Use the gemini_pro provider
      provider = 'gemini_pro',
      auto_suggestions_provider = 'gemini',
      behaviour = {
        enable_token_counting = false,
        auto_approve_tool_permissions = true,
        auto_suggestions = true,
      },
      mappings = {
        sidebar = {
          edit_user_request = 'u',
        },
      },
      providers = {
        gemini = {
          api_key_name = { 'cat', '~/.config/ai-keys/gemini' },
          model = 'gemini-2.5-flash',
        },
        gemini_pro = {
          __inherited_from = "gemini",
          model = 'gemini-2.5-pro',
        },
        openai = {
          api_key_name = { 'cat', '~/.config/ai-keys/openai' },
        },
        ["o4-mini"] = {
          __inherited_from = "openai",
          model = "o4-mini",
        },
        claude = {
          api_key_name = { 'cat', '~/.config/ai-keys/anthropic' },
        },
        openrouter = {
          __inherited_from = "openai",
          endpoint = "https://openrouter.ai/api/v1",
          api_key_name = { 'cat', '~/.config/ai-keys/openrouter' },
          timeout = 30000, -- Timeout in milliseconds
          context_window = 200000,
          extra_request_body = {
            temperature = 0.75,
            max_tokens = 64000,
          },
        },
        ollama = {
          model = 'gemma3:4b',
        },
        claude_sonnet = {
          __inherited_from = "openai",
          model = "anthropic/claude-sonnet-4",
          endpoint = "https://openrouter.ai/api/v1",
          api_key_name = { 'cat', '~/.config/ai-keys/openrouter' },
          timeout = 30000, -- Timeout in milliseconds
          context_window = 200000,
          extra_request_body = {
            temperature = 0.75,
            max_tokens = 64000,
          },
        },
        claude_haiku = {
          __inherited_from = "openai",
          model = "anthropic/claude-3.5-haiku",
          endpoint = "https://openrouter.ai/api/v1",
          api_key_name = { 'cat', '~/.config/ai-keys/openrouter' },
          timeout = 30000, -- Timeout in milliseconds
          context_window = 200000,
          extra_request_body = {
            temperature = 0.75,
            max_tokens = 64000,
          },
        },
        kimi_k2 = {
          __inherited_from = "openai",
          model = "moonshotai/kimi-k2",
          endpoint = "https://openrouter.ai/api/v1",
          api_key_name = { 'cat', '~/.config/ai-keys/openrouter' },
          timeout = 30000, -- Timeout in milliseconds
          context_window = 120000,
          extra_request_body = {
            temperature = 0.75,
            max_tokens = 64000,
          },
        },
      },
      rag_service = {
        enabled = false,
        llm = {
          provider = "ollama",
          endpoint = "http://localhost:11434",
          api_key = "",
          model = "gemma3:4b",
        },
        embed = {
          provider = "ollama",
          endpoint = "http://localhost:11434",
          api_key = "",
          model = "nomic-embed-text",
        },
        runner = "nix",
      },
      web_search_engine = {
        provider = 'google',
      },
      -- Enable MCP as the system prompt if it exists.
      system_prompt = function()
        local hub = require("mcphub").get_hub_instance()
        return hub and hub:get_active_servers_prompt() or ""
      end,
      custom_tools = function()
        local mcp_tools = require("mcphub.extensions.avante").mcp_tool()
        local custom_tools_path = vim.fn.expand("~/.config/custom_tools.lua")
        if vim.fn.filereadable(custom_tools_path) == 0 then
          -- This is not an error, as there may not be custom tools.
          return mcp_tools
        end
        local ok, result = pcall(dofile, custom_tools_path)
        if not ok then
          vim.notify("Failed to load custom tools from " .. custom_tools_path .. ": " .. result, vim.log.levels.ERROR)
          return mcp_tools
        end
        if type(result) ~= "table" then
          vim.notify("Custom tools file " .. custom_tools_path .. " did not return a table.", vim.log.levels.ERROR)
          return mcp_tools
        end
        return vim.tbl_deep_extend('keep', mcp_tools, result)
      end,
    },
  },
}
