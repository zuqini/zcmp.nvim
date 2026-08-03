local config = require('zcmp.config')
local helpers = require('helpers')
local sources = require('zcmp.sources')

---A provider module, registered the way `require` would find one.
---@param name string
---@param module table
local function register(name, module)
  helpers.stub(package.loaded, name, module)
end

---@param bufnr integer
---@param id string
---@return zcmp.ResolvedSource?
local function resolved(bufnr, id)
  for _, source in ipairs(sources.list(bufnr)) do
    if source.id == id then
      return source
    end
  end
  return nil
end

before_each(helpers.reset)
after_each(helpers.cleanup)

describe('source resolution', function()
  it("orders 'complete' the way the source list is written", function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'buffer', 'path' },
        providers = { buffer = { flags = { '.' }, max_items = 9 } },
      },
    })

    assert.are.equal(".^9," .. require('zcmp.sources.path').source(), sources.resolve(bufnr))
  end)

  it('caps each entry a provider contributes', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'buffer' } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
  end)

  it('falls back to the list-wide cap', function()
    local bufnr = helpers.buffer()
    config.setup({
      completion = { list = { max_items = 7 } },
      sources = { default = { 'spell' }, providers = { spell = { flags = { 'kspell' } } } },
    })

    assert.are.equal('kspell^7', sources.resolve(bufnr))
  end)

  it("takes a module's own 'complete' entry when it names one", function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() return 'Ffake' end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    assert.are.equal('Ffake', sources.resolve(bufnr))
  end)

  it('builds the entry itself for a module that only has completefunc', function()
    local bufnr = helpers.buffer()
    register('fake_source', { completefunc = function() return -2 end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    assert.are.equal([[Fv:lua.require'fake_source'.completefunc]], sources.resolve(bufnr))
  end)

  it('starts a provider module once, with its opts', function()
    local bufnr = helpers.buffer()
    local started = {}
    register('fake_source', {
      completefunc = function() end,
      enable = function(opts)
        started[#started + 1] = opts
      end,
    })
    config.setup({
      sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source', opts = { limit = 3 } } } },
    })

    sources.resolve(bufnr)
    sources.resolve(bufnr)
    assert.are.equal(1, #started)
    assert.are.same({ limit = 3 }, started[1])

    sources.reset()
    sources.resolve(bufnr)
    assert.are.equal(2, #started)
  end)

  -- The snippets provider is zsnip's, and a config that lists it without
  -- installing zsnip must still complete everything else.
  it('keeps the other sources when a provider module is missing', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'snippets', 'buffer' } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
    assert.is_true(resolved(bufnr, 'snippets').problem:find('zsnip.complete', 1, true) ~= nil)
  end)

  it('reports a module that serves no matches', function()
    local bufnr = helpers.buffer()
    register('fake_source', {})
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    assert.is_true(resolved(bufnr, 'fake').problem:find('serves no matches', 1, true) ~= nil)
  end)

  it('reports a source list naming a provider that does not exist', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'nope' } } })

    assert.are.equal('no such provider', resolved(bufnr, 'nope').problem)
    assert.are.equal('', sources.resolve(bufnr))
  end)

  it('skips a disabled provider', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'buffer', 'path' },
        providers = { path = { enabled = false }, buffer = { enabled = function() return true end } },
      },
    })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
    assert.are.equal('disabled', resolved(bufnr, 'path').problem)
  end)

  it('skips a provider with nothing to offer this buffer', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'buffer' },
        providers = { buffer = { available = function() return false end } },
      },
    })

    assert.are.equal('unavailable in this buffer', resolved(bufnr, 'buffer').problem)
  end)

  -- The LSP source is the omnifunc, and there is nothing to ask until a server
  -- that answers completion is attached.
  it('leaves the omnifunc out until a client can answer', function()
    local bufnr = helpers.buffer()
    config.setup({})

    assert.is_false(resolved(bufnr, 'lsp').active)
    assert.are.same({}, resolved(bufnr, 'lsp').entries)
  end)

  it('takes a filetype list over the default one', function()
    local bufnr = helpers.buffer()
    vim.bo[bufnr].filetype = 'lua'
    config.setup({ sources = { default = { 'path' }, per_filetype = { lua = { 'buffer' } } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
  end)

  it('adds to the default list when the filetype list inherits it', function()
    local bufnr = helpers.buffer()
    vim.bo[bufnr].filetype = 'lua'
    register('fake_source', { source = function() return 'Ffake' end })
    config.setup({
      sources = {
        default = { 'buffer' },
        per_filetype = { lua = { inherit_defaults = true, 'fake' } },
        providers = { fake = { module = 'fake_source' } },
      },
    })

    assert.are.equal('.^100,w^100,b^100,Ffake', sources.resolve(bufnr))
  end)

  it('names a provider once, however often the list does', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'buffer', 'buffer' } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
  end)

  it('hands back the provider a buffer names, availability aside', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'lsp', 'buffer' } } })

    assert.are.equal('LSP', (sources.provider(bufnr, 'lsp') or {}).name)
    assert.is_nil(sources.provider(bufnr, 'path'))
    assert.is_nil(sources.provider(bufnr, 'nope'))
  end)

  -- `:ZCmp status` and `:checkhealth zcmp` both reach list(). A diagnostic
  -- that configures the plugin it is diagnosing is the worst kind to read.
  it('starts a provider module on the way to writing the option, not to report', function()
    local bufnr = helpers.buffer()
    local started = 0
    register('fake_source', {
      source = function()
        return 'Ffake'
      end,
      enable = function()
        started = started + 1
      end,
    })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    sources.list(bufnr)
    assert.are.equal(0, started)

    sources.resolve(bufnr)
    sources.resolve(bufnr)
    assert.are.equal(1, started)
  end)

  it('reports a module whose enable() raises, and does not retry it', function()
    local bufnr = helpers.buffer()
    local tries = 0
    register('fake_source', {
      source = function()
        return 'Ffake'
      end,
      enable = function()
        tries = tries + 1
        error('no')
      end,
    })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    assert.are.equal('', sources.resolve(bufnr))
    assert.are.equal('', sources.resolve(bufnr))
    assert.are.equal(1, tries)
    assert.is_true(resolved(bufnr, 'fake').problem:find('failed to start', 1, true) ~= nil)
  end)

  -- Anything a provider declares can be somebody else's function, and the list
  -- is what `:checkhealth` reads: one of them raising is that provider's
  -- problem, not the list's.
  it('reports a provider whose available() raises', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'bad', 'buffer' },
        providers = {
          bad = {
            flags = { '.' },
            available = function()
              error('no')
            end,
          },
        },
      },
    })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
    assert.is_false(resolved(bufnr, 'bad').active)
    assert.is_not_nil(resolved(bufnr, 'bad').problem)
  end)

  -- A provider may declare both; the flags still serve when the module does
  -- not, and hiding that behind a tick is what checkhealth exists to prevent.
  it('keeps the problem of a provider that serves its flags anyway', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'half' },
        providers = { half = { flags = { '.' }, module = 'no_such_module' } },
      },
    })

    local source = resolved(bufnr, 'half')
    assert.is_true(source.active)
    assert.is_true(source.problem:find('not on the runtimepath', 1, true) ~= nil)
  end)

  it('hands back nothing for a provider the buffer has switched off', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'lsp' },
        providers = { lsp = { enabled = false } },
      },
    })

    assert.is_nil(sources.provider(bufnr, 'lsp'))
  end)
end)
