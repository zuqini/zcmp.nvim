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

  it('restores the defaults', function()
    config.setup({ sources = { default = { 'buffer' } } })
    config.reset()

    assert.are.same({ 'lsp', 'path', 'snippets', 'buffer' }, config.options.sources.default)
  end)
end)
