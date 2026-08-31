local config = require('zcmp.config')
local helpers = require('helpers')

after_each(helpers.cleanup)

describe('config', function()
  it('works before setup() has run', function()
    assert.are.same({ 'lsp', 'path', 'snippets', 'buffer' }, config.options.sources.default)
    assert.are.equal('default', config.options.keymap.preset)
  end)

  it('keeps the defaults a partial config does not mention', function()
    config.setup({ keymap = { preset = 'enter' } })

    assert.are.equal('enter', config.options.keymap.preset)
    assert.is_true(config.options.completion.menu.auto_show)
    assert.is_true(config.options.completion.list.selection.preselect)
  end)

  -- A source list is a choice of sources, not an addition to one: merging it
  -- key by key would leave `default = { 'buffer' }` still serving four.
  it('replaces a list rather than extending it', function()
    config.setup({ sources = { default = { 'buffer' } } })

    assert.are.same({ 'buffer' }, config.options.sources.default)
  end)

  it('merges a provider over the built-in one of the same id', function()
    config.setup({ sources = { providers = { snippets = { max_items = 5 } } } })

    local snippets = config.options.sources.providers.snippets
    assert.are.equal(5, snippets.max_items)
    assert.are.equal('zsnip.complete', snippets.module)
    assert.is_false(snippets.opts.complete)
  end)

  it('keeps a provider of its own alongside the built-in ones', function()
    config.setup({ sources = { providers = { spell = { flags = { 'kspell' } } } } })

    assert.are.same({ 'kspell' }, config.options.sources.providers.spell.flags)
    assert.is_not_nil(config.options.sources.providers.path)
  end)

  it('reports an unknown option by its full path', function()
    local notified = helpers.notifications(function()
      config.setup({ completion = { menu = { auto_shwo = true } } })
    end)

    assert.is_true(helpers.notified(notified, 'completion.menu.auto_shwo'))
  end)

  -- An unknown key is a silent no-op either way; pruning it too keeps the
  -- resolved config the declared shape rather than carrying dead weight.
  it('prunes an unknown key rather than keeping it', function()
    helpers.notifications(function()
      config.setup({ completion = { list = { max_item = 5 } } })
    end)

    assert.is_nil(config.options.completion.list.max_item)
  end)

  it('reports a known option of the wrong type', function()
    local notified = helpers.notifications(function()
      config.setup({ completion = { menu = { auto_show = 'yes' } } })
    end)

    assert.is_true(helpers.notified(notified, 'completion.menu.auto_show should be boolean'))
  end)

  -- A wrong-typed leaf must default exactly as a wrong-typed table does,
  -- rather than land in ResolvedConfig as though it had passed the check.
  it('defaults a scalar leaf of the wrong type instead of keeping it', function()
    helpers.notifications(function()
      config.setup({ completion = { menu = { auto_show = 'yes' } } })
    end)

    assert.is_true(config.options.completion.menu.auto_show)
  end)

  -- `kind_hl` accepts a string or the literal `false` -- a value of neither
  -- shape is what config-level pruning defaults here.
  it('defaults a string-or-false leaf handed neither shape', function()
    helpers.notifications(function()
      config.setup({ appearance = { kind_hl = 5 } })
    end)

    assert.are.equal('Special', config.options.appearance.kind_hl)
  end)

  -- `true` is not the shape's `false`, so it is pruned and reported here
  -- like any other wrong-typed value, rather than reaching appearance.lua.
  it('reports appearance.kind_hl of true rather than admitting it as a boolean', function()
    local notified = helpers.notifications(function()
      config.setup({ appearance = { kind_hl = true } })
    end)

    assert.are.equal('Special', config.options.appearance.kind_hl)
    assert.is_true(helpers.notified(notified, 'appearance.kind_hl should be string or false, got boolean'))
  end)

  it('defaults a function-shaped leaf handed the wrong type', function()
    local default_enabled = config.options.enabled
    helpers.notifications(function()
      config.setup({ enabled = true })
    end)

    assert.are.equal(default_enabled, config.options.enabled)
  end)

  it('still applies a valid sibling in the same table as a wrong-typed leaf', function()
    helpers.notifications(function()
      config.setup({ completion = { menu = { auto_show = 'yes' } }, keymap = { preset = 'enter' } })
    end)

    assert.are.equal('enter', config.options.keymap.preset)
  end)

  it('reports an unknown key inside a provider', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { path = { modul = 'x' } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.path.modul'))
  end)

  -- The `lsp` provider's `opts` keys are zcmp's own, so they are shaped like
  -- any other option -- keyed on the module the provider reaches, not its id.
  -- Pruned to nothing, the `opts` defaults whole rather than merging `{}`.
  it("reports an unknown key in the lsp provider's opts and keeps the default", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { lsp = { opts = { autotriger = false } } } } })
    end)

    assert.is_true(helpers.notified(notified, 'unknown option "sources.providers.lsp.opts.autotriger"'))
    assert.is_true(config.options.sources.providers.lsp.opts.autotrigger)
    assert.is_true(config.options.sources.providers.lsp.opts.extend_trigger_characters)
  end)

  it("reports a wrong-typed value in the lsp provider's opts and keeps the default", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { lsp = { opts = { autotrigger = 'off' } } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.lsp.opts.autotrigger should be boolean, got string'))
    assert.is_true(config.options.sources.providers.lsp.opts.autotrigger)
  end)

  it("applies a valid lsp opts value without a report", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { lsp = { opts = { autotrigger = false } } } } })
    end)

    assert.are.same({}, notified)
    assert.is_false(config.options.sources.providers.lsp.opts.autotrigger)
  end)

  it("reports an unknown key in the path provider's opts", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { path = { opts = { limt = 10 } } } } })
    end)

    assert.is_true(helpers.notified(notified, 'unknown option "sources.providers.path.opts.limt"'))
  end)

  it("reports a wrong-typed path limit at setup() and leaves no opts behind", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { path = { opts = { limit = '10' } } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.path.opts.limit should be number, got string'))
    assert.is_nil(config.options.sources.providers.path.opts)
  end)

  it("leaves the lsp provider's opts opaque once its module is not zcmp's", function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { lsp = { module = 'my.lsp', opts = { anything = 1 } } } } })
    end)

    assert.are.same({}, notified)
    assert.are.equal(1, config.options.sources.providers.lsp.opts.anything)
  end)

  -- The module the check follows is the one `resolve()` reaches: a
  -- registration or the luasnip preset re-points an id underneath setup()'s
  -- own table, and reading DEFAULTS alone missed both.
  it("leaves the lsp provider's opts opaque once a registration re-pointed its module", function()
    config.add_source_provider('lsp', { module = 'my.lsp' })
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { lsp = { opts = { foo = true } } } } })
    end)

    assert.are.same({}, notified)
    assert.is_true(config.options.sources.providers.lsp.opts.foo)
  end)

  it("shapes the snippets provider's opts once the luasnip preset points it at the adapter", function()
    local notified = helpers.notifications(function()
      config.setup({
        snippets = { preset = 'luasnip' },
        sources = { providers = { snippets = { opts = { documentation = 'no' } } } },
      })
    end)

    assert.is_true(
      helpers.notified(notified, 'sources.providers.snippets.opts.documentation should be boolean, got string')
    )
  end)

  it("reports an unknown key in the luasnip adapter's opts", function()
    local notified = helpers.notifications(function()
      config.setup({
        snippets = { preset = 'luasnip' },
        sources = { providers = { snippets = { opts = { show_condtion = function() end } } } },
      })
    end)

    assert.is_true(helpers.notified(notified, 'unknown option "sources.providers.snippets.opts.show_condtion"'))
  end)

  -- Pointing a shipped provider at another module drops the shipped module's
  -- `opts` with it: zsnip's coordination keys are zsnip's, and a map-merge
  -- used to hand them to whatever module took its place.
  it("drops the shipped module's opts when the snippets provider is re-pointed", function()
    config.setup({ sources = { providers = { snippets = { module = 'my.snippet.source' } } } })

    local opts = config.options.sources.providers.snippets.opts or {}
    assert.is_nil(opts.complete)
    assert.is_nil(opts.expand)
  end)

  -- The default `expand` opt exists so a preset still applies to zsnip, so
  -- naming zsnip's module again over the luasnip preset must bring the
  -- shipped default's opts back rather than leave zsnip to append itself.
  it("brings the shipped default's opts back when its module is named over a preset", function()
    config.setup({
      snippets = { preset = 'luasnip' },
      sources = { providers = { snippets = { module = 'zsnip.complete' } } },
    })

    local opts = config.options.sources.providers.snippets.opts
    assert.is_false(opts.complete)
    assert.are.equal('function', type(opts.expand))
  end)

  it("leaves a re-pointed provider's own opts standing alone", function()
    local notified = helpers.notifications(function()
      config.setup({
        sources = { providers = { snippets = { module = 'my.snippet.source', opts = { mine = 1 } } } },
      })
    end)

    assert.are.same({}, notified)
    assert.are.same({ mine = 1 }, config.options.sources.providers.snippets.opts)
  end)

  -- Pruning a wrong-typed list element used to leave it in place so `ipairs`
  -- would not stop at the hole; the list is compacted instead, so the element
  -- can be reported and dropped like any other wrong-typed value, and the
  -- rest keep their order.
  it('reports a wrong-typed list element and drops it, the rest keep their order', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { default = { 'lsp', 1, 'buffer' } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.default.2 should be string'))
    assert.are.same({ 'lsp', 'buffer' }, config.options.sources.default)
  end)

  -- `sources.default`'s shape is a list -- a key the user names there
  -- (`lsp = 'lsp'`, a typo for a positional entry) is not one of its
  -- positions, and must not be checked as though it were one.
  it('reports a string key in sources.default as an unknown option, not an element', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { default = { lsp = 'lsp' } } })
    end)

    assert.is_true(helpers.notified(notified, 'unknown option "sources.default.lsp"'))
    assert.are.same({ 'lsp', 'path', 'snippets', 'buffer' }, config.options.sources.default)
  end)

  it('reports a per_filetype list element of the wrong type', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { per_filetype = { lua = { 1 } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.per_filetype.lua.1 should be string'))
  end)

  -- `inherit_default` (no `s`) is a typo, not a positional entry -- reported
  -- as an unknown option rather than borrowed as the element shape.
  it('reports a typo in a per_filetype entry as an unknown option', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { per_filetype = { lua = { inherit_default = 'yes', 'mine' } } } })
    end)

    assert.is_true(helpers.notified(notified, 'unknown option "sources.per_filetype.lua.inherit_default"'))
    assert.are.same({ 'mine' }, config.options.sources.per_filetype.lua)
  end)

  -- pairs(string) raises: a mistyped call must warn and fall back to the
  -- defaults, not take the whole config down with it.
  it('proceeds with the defaults when handed something other than a table', function()
    local notified = helpers.notifications(function()
      config.setup('enter')
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.setup: expected a table'))
    assert.are.equal('default', config.options.keymap.preset)
  end)

  -- A keymap's keys and a per_filetype's filetypes are the user's to name.
  it('takes any key under keymap and per_filetype', function()
    local notified = helpers.notifications(function()
      config.setup({
        keymap = { ['<C-j>'] = { 'select_next' } },
        sources = { per_filetype = { lua = { 'buffer' } } },
      })
    end)

    assert.are.equal(0, #notified)
    assert.are.same({ 'select_next' }, config.options.keymap['<C-j>'])
  end)

  it('keeps a keymap entry of false rather than pruning it', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { ['<C-e>'] = false } })
    end)

    assert.are.equal(0, #notified)
    assert.are.equal(false, config.options.keymap['<C-e>'])
  end)

  -- `true` is not the shape's `false`, so it is pruned and reported here --
  -- the entry never reaches keymap.lua at all.
  it('reports a keymap entry of true rather than admitting it as a boolean', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { ['<CR>'] = true } })
    end)

    assert.is_nil(config.options.keymap['<CR>'])
    assert.is_true(helpers.notified(notified, 'keymap.<CR> should be table or false, got boolean'))
  end)

  -- keymap is a map keyed by lhs, not a list -- a stray numeric key must be
  -- dropped like any other wrong-typed value, not kept in place the way a
  -- real list's element is; keeping it once threw away `preset` too, since
  -- vim.islist() then saw the surviving numeric key and replaced the whole
  -- table.
  it('drops a numeric keymap key rather than keeping it in place', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { 'super-tab' } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.1 should be a key, got number'))
    assert.are.equal('default', config.options.keymap.preset)
    assert.is_nil(config.options.keymap[1])
  end)

  -- keymap is a map, so a numeric key is wrong regardless of what its value
  -- looks like -- a value that itself passes the entry shape must not sail
  -- through the way `list_shaped()` once let it.
  it('drops a numeric keymap key whose value is a table entry', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { { 'accept' } } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.1 should be a key, got number'))
    assert.are.equal('default', config.options.keymap.preset)
    assert.is_nil(config.options.keymap[1])
  end)

  it('drops a numeric keymap key alongside an explicit preset', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'enter', { 'accept' } } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.1 should be a key, got number'))
    assert.are.equal('enter', config.options.keymap.preset)
    assert.is_nil(config.options.keymap[1])
  end)

  it('drops a numeric keymap key whose value is false', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { false } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.1 should be a key, got number'))
    assert.are.equal('default', config.options.keymap.preset)
    assert.is_nil(config.options.keymap[1])
  end)

  it('applies the rest of a config that is wrong in one place', function()
    helpers.notifications(function()
      config.setup({ signature = { enabled = 'yes' }, keymap = { preset = 'enter' } })
    end)

    assert.are.equal('enter', config.options.keymap.preset)
  end)

  -- An empty list is the same instruction as a short one, and the only way to
  -- say "nothing here"; `:checkhealth zcmp` reports it as the error it is.
  it('takes an empty list as a real choice of no sources', function()
    config.setup({ sources = { default = {} } })

    assert.are.same({}, config.options.sources.default)
  end)

  -- `{}` and an empty list are the same shape, so the default has to decide:
  -- over a map it means "nothing to say", not "wipe it".
  it('leaves a map alone when handed an empty table', function()
    config.setup({ sources = { providers = {} }, completion = { menu = {} } })

    assert.is_not_nil(config.options.sources.providers.path)
    assert.is_true(config.options.completion.menu.auto_show)
  end)

  -- A provider's `opts` is free-form third-party data, so one that happens to
  -- carry positional entries is still a map. Replacing it wholesale would drop
  -- the keys zcmp sets, and `complete = false` is what keeps zsnip out of the
  -- option `buffer.lua` is the single writer of.
  it('merges a provider opts table that has an array part', function()
    config.setup({ sources = { providers = { snippets = { opts = { 'lua', limit = 5 } } } } })

    local opts = config.options.sources.providers.snippets.opts
    assert.are.equal(5, opts.limit)
    assert.is_false(opts.complete)
  end)

  -- `{ 'lsp', want_snippets and 'snippets' or nil, 'buffer' }` is a table with
  -- a hole -- `ipairs` stops at one, and merging by index instead of
  -- compacting used to fill the hole from the defaults, bringing back the
  -- source the idiom just switched off.
  it('compacts a list with a hole in it rather than index-merging over the defaults', function()
    config.setup({ sources = { default = { 'lsp', nil, 'buffer' } } })

    assert.are.same({ 'lsp', 'buffer' }, config.options.sources.default)
  end)

  -- The `want_snippets and 'snippets' or nil` idiom leaves a hole at that
  -- position; it must switch the source off, not bring it back from the
  -- defaults it was merged against.
  it('turns off a source the want_snippets idiom held out', function()
    local want_snippets = false
    config.setup({ sources = { default = { 'lsp', 'path', want_snippets and 'snippets' or nil, 'buffer' } } })

    assert.are.same({ 'lsp', 'path', 'buffer' }, config.options.sources.default)
  end)

  -- `flags` used to be a bare `table`, so `{ '.', want and 'w' or nil, 'b' }`
  -- with `want` false left a hole that index-merging over the default flags
  -- filled back in -- the flag the idiom just switched off came back.
  it('compacts a provider flags hole rather than index-merging over the defaults', function()
    local want = false
    config.setup({ sources = { providers = { buffer = { flags = { '.', want and 'w' or nil, 'b' } } } } })

    assert.are.same({ '.', 'b' }, config.options.sources.providers.buffer.flags)
  end)

  -- Dropping the only element empties the list, and a table that lost every
  -- entry defaults like any other wrong-typed value -- so `flags` keeps the
  -- built-in provider's own default rather than coming back empty.
  it('reports a wrong-typed provider flag and defaults the whole list', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { buffer = { flags = { 1 } } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.buffer.flags.1 should be string'))
    assert.are.same({ '.', 'w', 'b' }, config.options.sources.providers.buffer.flags)
  end)

  -- `{ 'accept', want and 'snippet_forward' or nil, 'fallback' }` with `want`
  -- false left the same kind of hole: `ipairs` never reached `fallback`, and
  -- the key was swallowed with the menu closed.
  it('compacts a keymap entry hole rather than index-merging over the defaults', function()
    local want = false
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'accept', want and 'snippet_forward' or nil, 'fallback' } } })

    assert.are.same({ 'accept', 'fallback' }, config.options.keymap['<Tab>'])
  end)

  it('reports a wrong-typed keymap command and drops it, the rest keep their order', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'accept', 42 } } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.<Tab>.2 should be string or function'))
    assert.are.same({ 'accept' }, config.options.keymap['<Tab>'])
  end)

  -- The base decides whether `{}` empties, and a per_filetype entry that came
  -- from a registration is a SourceList -- which vim.islist alone says no to.
  it('takes an empty list over a registered filetype list', function()
    config.add_filetype_source('lua', { 'path' })
    config.setup({ sources = { per_filetype = { lua = {} } } })

    assert.are.same({}, config.options.sources.per_filetype.lua)
  end)

  it('does not keep a reference to the table it was handed', function()
    local per_filetype = { markdown = { 'path' } }
    config.setup({ sources = { per_filetype = per_filetype } })

    config.add_filetype_source('markdown', 'buffer')

    assert.are.same({ 'path' }, per_filetype.markdown)
  end)

  it('says nothing about the snippets preset it does have', function()
    local notified = helpers.notifications(function()
      config.setup({ snippets = { preset = 'default' } })
    end)

    assert.are.equal(0, #notified)
  end)

  it('restores the defaults', function()
    config.setup({ sources = { default = { 'buffer' } } })
    config.reset()

    assert.are.same({ 'lsp', 'path', 'snippets', 'buffer' }, config.options.sources.default)
  end)
end)

-- A plugin registering a source from its own config block runs before the
-- user's setup() as often as after, and setup() replaces `options` wholesale.
describe('registering outside setup()', function()
  it('keeps a provider registered before setup() ran', function()
    config.add_source_provider('spell', { flags = { 'kspell' } })
    config.setup({ sources = { default = { 'spell' } } })

    assert.are.same({ 'kspell' }, config.options.sources.providers.spell.flags)
  end)

  it('keeps a filetype source registered before setup() ran', function()
    config.add_filetype_source('markdown', { 'path' })
    config.setup({})

    local markdown = config.options.sources.per_filetype.markdown
    assert.are.same({ 'path' }, { unpack(markdown) })
    assert.is_true(markdown.inherit_defaults)
  end)

  it('lets an explicit setup() win over an earlier registration', function()
    config.add_source_provider('spell', { flags = { 'kspell' } })
    config.setup({ sources = { providers = { spell = { flags = { 'k/usr/share/dict/words' } } } } })

    assert.are.same({ 'k/usr/share/dict/words' }, config.options.sources.providers.spell.flags)
  end)

  it('takes effect straight away when setup() has already run', function()
    config.setup({})
    config.add_source_provider('spell', { flags = { 'kspell' } })
    config.add_filetype_source('markdown', 'spell')

    assert.is_not_nil(config.options.sources.providers.spell)
    assert.contains(config.options.sources.per_filetype.markdown, 'spell')
  end)

  it('names a provider once, however often it is added', function()
    config.add_filetype_source('markdown', 'path')
    config.add_filetype_source('markdown', { 'path', 'buffer' })
    config.setup({})

    assert.are.same({ 'path', 'buffer' }, { unpack(config.options.sources.per_filetype.markdown) })
  end)

  -- A hole in the list handed to add_filetype_source (the same
  -- `cond and 'x' or nil` idiom) must not lose everything past it the way an
  -- uncompacted `ipairs` would.
  it('keeps every id after a hole handed to add_filetype_source', function()
    config.add_filetype_source('lua', { 'lazydev', nil, 'mine' })
    config.setup({})

    local lua = config.options.sources.per_filetype.lua
    assert.contains(lua, 'lazydev')
    assert.contains(lua, 'mine')
  end)

  -- A `zcmp.SourceList` carries `inherit_defaults` alongside its entries, so
  -- vim.islist says no and it used to merge key by key -- which merges the
  -- entries by index, leaving whatever the registration had put beyond the end
  -- of the user's list still in it.
  it('replaces a filetype list a registration had added to', function()
    config.add_filetype_source('lua', { 'lazydev', 'snacks' })
    config.setup({ sources = { per_filetype = { lua = { inherit_defaults = true, 'mine' } } } })

    local lua = config.options.sources.per_filetype.lua
    assert.are.same({ 'mine' }, { unpack(lua) })
    assert.is_true(lua.inherit_defaults)
  end)

  it('reports an unknown key in a provider registered outside setup()', function()
    local notified = helpers.notifications(function()
      config.add_source_provider('spell', { flag = { 'kspell' } })
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.add_source_provider: unknown option'))
    assert.is_true(helpers.notified(notified, 'sources.providers.spell.flag'))
  end)

  -- A registration replaces the shipped provider wholesale, so its opts are
  -- shaped by the module the registration itself names -- and one naming no
  -- module reaches none, so there is nothing to shape them against.
  it("reports an unknown key in a registration's opts once it names a shipped module", function()
    local notified = helpers.notifications(function()
      config.add_source_provider('lsp', { module = 'zcmp.lsp', opts = { autotriger = true } })
    end)

    assert.is_true(
      helpers.notified(notified, 'zcmp.add_source_provider: unknown option "sources.providers.lsp.opts.autotriger"')
    )
  end)

  it("leaves a registration's opts opaque when it names no module", function()
    local notified = helpers.notifications(function()
      config.add_source_provider('lsp', { opts = { autotriger = true } })
    end)

    assert.are.same({}, notified)
    assert.is_nil(config.options.sources.providers.lsp.module)
    assert.is_true(config.options.sources.providers.lsp.opts.autotriger)
  end)

  it("shapes a registration's opts by its own module, and drops them once setup() re-points the id", function()
    local notified = helpers.notifications(function()
      config.add_source_provider('snippets', { module = 'my.mod', opts = { foo = 1 } })
    end)

    assert.are.same({}, notified)
    assert.are.equal(1, config.options.sources.providers.snippets.opts.foo)

    notified = helpers.notifications(function()
      config.setup({ sources = { providers = { snippets = { module = 'zcmp.sources.snippets.luasnip' } } } })
    end)

    assert.are.same({}, notified)
    assert.is_nil((config.options.sources.providers.snippets.opts or {}).foo)
  end)

  it("does not shape a registration's opts by the module an earlier setup() named", function()
    config.setup({ sources = { providers = { snippets = { module = 'zcmp.sources.snippets.luasnip' } } } })
    local notified = helpers.notifications(function()
      config.add_source_provider('snippets', { module = 'my.mod', opts = { foo = 1 } })
    end)

    assert.are.same({}, notified)
    assert.are.equal('zcmp.sources.snippets.luasnip', config.options.sources.providers.snippets.module)
    assert.is_nil((config.options.sources.providers.snippets.opts or {}).foo)
  end)

  it("gives a registration its opts back once setup() stops re-pointing the id", function()
    config.add_source_provider('foo', { module = 'a', opts = { x = 1 } })
    config.setup({ sources = { providers = { foo = { module = 'b' } } } })
    config.setup({})

    assert.are.equal('a', config.options.sources.providers.foo.module)
    assert.are.same({ x = 1 }, config.options.sources.providers.foo.opts)
  end)

  it("does not hand a registration the shipped opts an earlier setup() brought back", function()
    config.add_source_provider('snippets', { module = 'mine', opts = { x = 1 } })
    config.setup({
      snippets = { preset = 'luasnip' },
      sources = { providers = { snippets = { module = 'zsnip.complete' } } },
    })
    config.setup({})

    assert.are.equal('mine', config.options.sources.providers.snippets.module)
    assert.are.same({ x = 1 }, config.options.sources.providers.snippets.opts)
  end)

  -- A string id no provider answers to is added anyway, as setup() would --
  -- that is `:ZCmp status`'s "no such provider", not a reason to drop it.
  it('reports and registers a filetype source that is no provider id', function()
    config.add_filetype_source('markdown', { 'nosuchprovider' })

    assert.contains(config.options.sources.per_filetype.markdown, 'nosuchprovider')
  end)

  -- Every element is non-string here, so it is dropped like any other
  -- wrong-typed value -- and that empties the list, which used to still file
  -- `per_filetype.markdown = { inherit_defaults = true }`: an entry naming no
  -- sources, indistinguishable from `sources.default`, for a call that named
  -- none.
  it('reports a filetype source list of nothing but wrong-typed elements, and files nothing', function()
    local notified = helpers.notifications(function()
      config.add_filetype_source('markdown', { 1 })
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.add_filetype_source: sources.per_filetype.markdown.1'))
    assert.is_nil(config.options.sources.per_filetype.markdown)
  end)

  -- It would file an entry naming no sources, which resolves to exactly
  -- `sources.default`: a call that did nothing and said nothing.
  it('reports a filetype source with no ids at all', function()
    local notified = helpers.notifications(function()
      config.add_filetype_source('markdown', {})
    end)

    assert.is_true(helpers.notified(notified, 'no provider ids'))
    assert.is_nil(config.options.sources.per_filetype.markdown)
  end)

  -- The one thing that cannot be reported and carried on with: it is the key a
  -- source list looks the entry up by.
  it('refuses a filetype that is no filetype', function()
    local notified = helpers.notifications(function()
      config.add_filetype_source({}, 'path')
      config.add_source_provider(1, { flags = { 'kspell' } })
    end)

    assert.is_true(helpers.notified(notified, 'filetype should be a string, got table'))
    assert.is_true(helpers.notified(notified, 'id should be a string, got number'))
    assert.are.same({}, config.options.sources.per_filetype)
  end)

  it('does not keep a reference to the provider it was handed', function()
    local provider = { flags = { 'kspell' } }
    config.add_source_provider('spell', provider)

    provider.flags[1] = 'k/usr/share/dict/words'
    config.setup({})

    assert.are.same({ 'kspell' }, config.options.sources.providers.spell.flags)
  end)

  -- A registration made after setup() used to write straight into the live
  -- `options`, so an explicit list only won when it ran second. Both orders
  -- must resolve the same explicit list, since a plugin registering from its
  -- own config block runs before the user's setup() as often as after.
  it('lets an explicit setup() win over a registration made after it too', function()
    config.setup({ sources = { per_filetype = { lua = { 'mine' } } } })
    config.add_filetype_source('lua', { 'lazydev' })

    assert.are.same({ 'mine' }, config.options.sources.per_filetype.lua)
  end)

  it('lets an explicit provider opts win over a registration made after it too', function()
    config.setup({ sources = { providers = { lazydev = { max_items = 5 } } } })
    config.add_source_provider('lazydev', { module = 'lazydev.completion', opts = { a = 1 } })

    local lazydev = config.options.sources.providers.lazydev
    assert.are.equal(5, lazydev.max_items)
    assert.are.equal('lazydev.completion', lazydev.module)
    assert.are.equal(1, lazydev.opts.a)
  end)

  it('does not raise when a provider registration is not a table', function()
    local notified = helpers.notifications(function()
      config.add_source_provider('x', 5)
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.x should be a table'))
    assert.is_nil(config.options.sources.providers.x)
  end)

  it('forgets registrations on reset', function()
    config.add_source_provider('spell', { flags = { 'kspell' } })
    config.reset()
    config.setup({})

    assert.is_nil(config.options.sources.providers.spell)
  end)
end)

describe('snippets preset', function()
  it("points the snippets provider at LuaSnip for 'luasnip'", function()
    config.setup({ snippets = { preset = 'luasnip' } })

    assert.are.equal('zcmp.sources.snippets.luasnip', config.options.sources.providers.snippets.module)
    assert.are.equal('luasnip', config.options.snippets.preset)
  end)

  it('asks LuaSnip first once the preset is on', function()
    local jumped
    helpers.stub(package.loaded, 'luasnip', {
      jumpable = function()
        return true
      end,
      jump = function(direction)
        jumped = direction
      end,
      lsp_expand = function() end,
      locally_jumpable = function()
        return true
      end,
      in_snippet = function()
        return true
      end,
    })
    config.setup({ snippets = { preset = 'luasnip' } })

    config.options.snippets.jump(1)

    assert.are.equal(1, jumped)
    assert.is_true(config.options.snippets.active())
    assert.is_true(config.options.snippets.active({ direction = -1 }))
  end)

  it('jumps with LuaSnip only where its session is, however far one is held', function()
    local luasnip_jumped, core_jumped = false, false
    helpers.stub(package.loaded, 'luasnip', {
      jumpable = function()
        return true
      end,
      locally_jumpable = function()
        return false
      end,
      in_snippet = function()
        return false
      end,
      jump = function()
        luasnip_jumped = true
      end,
      lsp_expand = function() end,
    })
    helpers.stub(vim.snippet, 'jump', function()
      core_jumped = true
    end)
    config.setup({ snippets = { preset = 'luasnip' } })

    config.options.snippets.jump(1)

    assert.is_false(luasnip_jumped)
    assert.is_true(core_jumped)
  end)

  it('falls through to vim.snippet when LuaSnip is not installed', function()
    package.loaded['luasnip'] = nil
    local jumped, expanded = false, nil
    helpers.stub(vim.snippet, 'jump', function()
      jumped = true
    end)
    helpers.stub(vim.snippet, 'expand', function(body)
      expanded = body
    end)
    config.setup({ snippets = { preset = 'luasnip' } })

    assert.is_false(config.options.snippets.active({ direction = 1 }))
    assert.is_false(config.options.snippets.active())
    config.options.snippets.jump(1)
    config.options.snippets.expand('$1')

    assert.is_true(jumped)
    assert.are.equal('$1', expanded)
  end)

  it('lets an explicit field beat its preset', function()
    local mine = function() end
    config.setup({
      snippets = { preset = 'luasnip', jump = mine },
      sources = { providers = { snippets = { module = 'zsnip.complete' } } },
    })

    assert.are.equal(mine, config.options.snippets.jump)
    assert.are.equal('zsnip.complete', config.options.sources.providers.snippets.module)
  end)

  it('says an unknown preset out loud, and known ones not at all', function()
    local notified = helpers.notifications(function()
      config.setup({ snippets = { preset = 'mini_snippets' } })
    end)
    assert.is_true(helpers.notified(notified, 'not a snippets preset'))

    notified = helpers.notifications(function()
      config.setup({ snippets = { preset = 'luasnip', expand = function() end } })
      config.setup({ snippets = { preset = 'default' } })
    end)
    assert.are.same({}, notified)
  end)

  it('says an unknown keymap preset out loud, naming the four it knows', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'supertab' } })
    end)

    assert.is_true(helpers.notified(notified, 'not a keymap preset'))
    assert.is_true(helpers.notified(notified, "'default', 'enter', 'none' and 'super-tab'"))
  end)
end)
