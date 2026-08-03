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
    assert.are.equal(200, config.options.completion.trigger.delay_ms)
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

  it('reports a known option of the wrong type', function()
    local notified = helpers.notifications(function()
      config.setup({ completion = { trigger = { delay_ms = '200' } } })
    end)

    assert.is_true(helpers.notified(notified, 'completion.trigger.delay_ms should be number'))
  end)

  it('reports an unknown key inside a provider', function()
    local notified = helpers.notifications(function()
      config.setup({ sources = { providers = { path = { modul = 'x' } } } })
    end)

    assert.is_true(helpers.notified(notified, 'sources.providers.path.modul'))
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
  -- a hole, and `ipairs` stops at one. Replacing with it would lose every entry
  -- past the hole with nothing said; merging keeps them reachable.
  it('does not replace a list with one that has a hole in it', function()
    config.setup({ sources = { default = { 'lsp', nil, 'buffer' } } })

    assert.contains(config.options.sources.default, 'buffer')
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

  it('reports the defaults it accepts but never calls', function()
    local notified = helpers.notifications(function()
      config.setup({ snippets = { expand = function() end, preset = 'luasnip' } })
    end)

    assert.is_true(helpers.notified(notified, 'snippets.expand is never called'))
    assert.is_true(helpers.notified(notified, 'is not a snippets preset'))
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
    config.add_provider('spell', { flags = { 'kspell' } })
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
    config.add_provider('spell', { flags = { 'kspell' } })
    config.setup({ sources = { providers = { spell = { flags = { 'k/usr/share/dict/words' } } } } })

    assert.are.same({ 'k/usr/share/dict/words' }, config.options.sources.providers.spell.flags)
  end)

  it('takes effect straight away when setup() has already run', function()
    config.setup({})
    config.add_provider('spell', { flags = { 'kspell' } })
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
      config.add_provider('spell', { flag = { 'kspell' } })
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.add_source_provider: unknown option'))
    assert.is_true(helpers.notified(notified, 'sources.providers.spell.flag'))
  end)

  -- Reported and registered anyway, as setup() would: an id no provider
  -- answers to is `:ZCmp status`'s "no such provider", not a reason to drop it.
  it('reports a filetype source that is no provider id', function()
    local notified = helpers.notifications(function()
      config.add_filetype_source('markdown', { 1 })
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.add_filetype_source: sources.per_filetype.markdown.1'))
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
      config.add_provider(1, { flags = { 'kspell' } })
    end)

    assert.is_true(helpers.notified(notified, 'filetype should be a string, got table'))
    assert.is_true(helpers.notified(notified, 'id should be a string, got number'))
    assert.are.same({}, config.options.sources.per_filetype)
  end)

  it('does not keep a reference to the provider it was handed', function()
    local provider = { flags = { 'kspell' } }
    config.add_provider('spell', provider)

    provider.flags[1] = 'k/usr/share/dict/words'
    config.setup({})

    assert.are.same({ 'kspell' }, config.options.sources.providers.spell.flags)
  end)

  it('forgets registrations on reset', function()
    config.add_provider('spell', { flags = { 'kspell' } })
    config.reset()
    config.setup({})

    assert.is_nil(config.options.sources.providers.spell)
  end)
end)
