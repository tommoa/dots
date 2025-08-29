local cmp = require('cmp')

local t = function(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

-- How this works:
--  - If we can complete, complete
--  - Otherwise, put in a tab
_G.tab_complete = function(_)
    if cmp.visible() then
        return cmp.confirm()
    else
        return t "<Tab>"
    end
end

-- I'd quite like control of my enter key back
-- I often find that with auto-complete on (and I always have it on), getting
-- to the end of a line without whitespace can be perilous, as the
-- auto-complete kicks in and decides to enter whatever it'd like when I hit
-- "enter" to go to a new line. This function fixes that
_G.do_enter_key = function(_)
    if cmp.visible() then
        -- Make sure compe closes so that floating windows get cleaned up
        cmp.close()
    end
    return t '<C-g>u<CR>'
end

cmp.setup {
  experimental = {
    ghost_text = true;
  };

  completion = {
    keyword_length = 1;
    completeopt = "menu,menuone,noinsert";
    -- autocomplete = true;
  };

  mapping = cmp.mapping.preset.insert({
    ['<Tab>'] = cmp.mapping(_G.tab_complete, { "i", "c" });
    ['<C-b>'] = cmp.mapping(cmp.mapping.scroll_docs(-4), { 'i', 'c' });
    ['<C-f>'] = cmp.mapping(cmp.mapping.scroll_docs(4), { 'i', 'c' });
    ['<C-e>'] = cmp.mapping({
      i = cmp.mapping.abort(),
      c = cmp.mapping.close(),
    });
  });

  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "path" },
    { name = "buffer" },
    { name = "calc" },
  });
}

cmp.setup.cmdline('/', {
  mapping = cmp.mapping.preset.cmdline({
      ['<C-n>'] = {
        c = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<C-p>'] = {
        c = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<Tab>'] = {
        c = cmp.mapping.confirm(),
      }
  });
  sources = cmp.config.sources({
    { name = 'nvim_lsp_document_symbol' }
  }, {
    { name = 'buffer' }
  })
})

cmp.setup.cmdline('?', {
  mapping = cmp.mapping.preset.cmdline({
      ['<C-n>'] = {
        c = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<C-p>'] = {
        c = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<Tab>'] = {
        c = cmp.mapping.confirm(),
      }
  });
  sources = cmp.config.sources({
    { name = 'nvim_lsp_document_symbol' }
  }, {
    { name = 'buffer' }
  })
})

cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline({
      ['<C-n>'] = {
        c = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<C-p>'] = {
        c = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
      };
      ['<Tab>'] = {
        c = cmp.mapping.confirm(),
      }
  });
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  })
})
