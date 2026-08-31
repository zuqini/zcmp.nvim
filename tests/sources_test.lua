local config = require('zcmp.config')
local helpers = require('helpers')
local sources = require('zcmp.sources')

local PATH_ENTRY = "Fv:lua.require'zcmp.sources.path'.completefunc"

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

    assert.are.equal(".^9," .. PATH_ENTRY, sources.resolve(bufnr))
  end)

  it('caps each entry a provider contributes', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'buffer' } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
  end)

  -- A non-integer or negative max_items raises E535 where it reaches
  -- 'complete', which would detach every buffer at once.
  it('floors a non-integer max_items and warns', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = { default = { 'buffer' }, providers = { buffer = { flags = { '.' }, max_items = 10.5 } } },
    })
    local complete
    local notified = helpers.notifications(function()
      complete = sources.resolve(bufnr)
    end)

    assert.are.equal('.^10', complete)
    assert.is_true(helpers.notified(notified, 'max_items'))
  end)

  it('writes a large max_items in full, never in exponent form', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = { default = { 'buffer' }, providers = { buffer = { flags = { '.' }, max_items = 1e14 } } },
    })

    assert.are.equal('.^100000000000000', sources.resolve(bufnr))
  end)

  it('drops a negative max_items rather than raising E535', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = { default = { 'buffer' }, providers = { buffer = { flags = { '.' }, max_items = -5 } } },
    })
    local complete
    local notified = helpers.notifications(function()
      complete = sources.resolve(bufnr)
    end)

    assert.are.equal('.', complete)
    assert.is_true(helpers.notified(notified, 'max_items'))
  end)

  it('falls back to the list-wide cap', function()
    local bufnr = helpers.buffer()
    config.setup({
      completion = { list = { max_items = 7 } },
      sources = { default = { 'spell' }, providers = { spell = { flags = { 'kspell' } } } },
    })

    assert.are.equal('kspell^7', sources.resolve(bufnr))
  end)

  -- The inherited cap used to be reported as `provider "<id>" max_items`,
  -- once per provider without one -- naming a field the user never wrote.
  it('reports a bad list-wide cap as its own field, once', function()
    local bufnr = helpers.buffer()
    config.setup({
      completion = { list = { max_items = 0.5 } },
      sources = {
        default = { 'spell', 'tags' },
        providers = { spell = { flags = { 'kspell' } }, tags = { flags = { 't' } } },
      },
    })
    local complete
    local notified = helpers.notifications(function()
      complete = sources.resolve(bufnr)
    end)

    assert.are.equal('kspell,t', complete)
    -- helpers.notifications() turns notify_once into notify, so "once" here
    -- is one distinct message: what notify_once collapses to.
    local distinct = {}
    for _, notification in ipairs(notified) do
      distinct[notification.message] = true
    end
    assert.are.equal(1, vim.tbl_count(distinct))
    assert.is_true(helpers.notified(notified, 'completion.list.max_items'))
    assert.is_false(helpers.notified(notified, 'provider'))
  end)

  it("reports a provider's own bad cap by provider", function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = { default = { 'buffer' }, providers = { buffer = { flags = { '.' }, max_items = 0.5 } } },
    })
    local notified = helpers.notifications(function()
      sources.resolve(bufnr)
    end)

    assert.is_true(helpers.notified(notified, 'provider "buffer" max_items'))
    assert.is_false(helpers.notified(notified, 'completion.list.max_items'))
  end)

  -- A flag that already carries its own count plus a `max_items` used to
  -- produce `.^50^100`, which 'complete' refuses with E535 and detaches
  -- every buffer -- the flag's own count wins instead.
  it("keeps a flag's own count rather than appending max_items to it", function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = { default = { 'buffer' }, providers = { buffer = { flags = { '.^50' }, max_items = 100 } } },
    })
    local complete
    local notified = helpers.notifications(function()
      complete = sources.resolve(bufnr)
    end)

    assert.are.equal('.^50', complete)
    assert.is_true(helpers.notified(notified, 'max_items'))
  end)

  -- The same E535 the flag case guards against, reached through a module's
  -- source() instead: a completefunc entry wrapped with its own count plus a
  -- `max_items` used to produce `^20^50`, and 'complete' rejects it whole.
  it("keeps a module's own count rather than appending max_items to it", function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() return 'Ffake^20' end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source', max_items = 50 } } } })
    local complete
    local notified = helpers.notifications(function()
      complete = sources.resolve(bufnr)
    end)

    assert.are.equal('Ffake^20', complete)
    assert.is_true(helpers.notified(notified, 'max_items'))
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

  -- `started` belongs to one resolved config. setup() replaces `options`
  -- wholesale, a provider's `opts` with them, so a module started from the
  -- previous set is holding options that have since been replaced. Nothing here
  -- calls sources.reset(): the point is that no call site has to remember to.
  it('starts a module again when the options are replaced', function()
    local bufnr = helpers.buffer()
    local started = {}
    register('fake_source', {
      completefunc = function() end,
      enable = function(opts)
        started[#started + 1] = opts
      end,
    })
    local function setup(limit)
      config.setup({
        sources = {
          default = { 'fake' },
          providers = { fake = { module = 'fake_source', opts = { limit = limit } } },
        },
      })
    end

    setup(1)
    sources.resolve(bufnr)
    sources.resolve(bufnr)
    setup(2)
    sources.resolve(bufnr)

    assert.are.same({ { limit = 1 }, { limit = 2 } }, started)
  end)

  -- The snippets provider is zsnip's, and a config that lists it without
  -- installing zsnip must still complete everything else.
  it('keeps the other sources when a provider module is missing', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'snippets', 'buffer' } } })

    assert.are.equal('.^100,w^100,b^100', sources.resolve(bufnr))
    assert.is_true(resolved(bufnr, 'snippets').problem:find('zsnip.complete', 1, true) ~= nil)
  end)

  -- pcall(require, ...) walks the whole runtimepath on a miss, and :ZCmp
  -- status / :checkhealth zcmp reach this on every BufEnter and FileType.
  it('does not require a missing module twice', function()
    local bufnr = helpers.buffer()
    local calls = 0
    local original_require = require
    helpers.stub(_G, 'require', function(name)
      if name == 'no_such_module_xyz' then
        calls = calls + 1
        error('module not found: ' .. name)
      end
      return original_require(name)
    end)
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'no_such_module_xyz' } } } })

    sources.resolve(bufnr)
    sources.resolve(bufnr)

    assert.are.equal(1, calls)
  end)

  -- require() raises the same way on a miss and on a module that loaded and
  -- then raised; only the miss names the module "not found" in its message.
  it('tells a module that raised while loading apart from one not installed', function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_boom', function()
      error('unexpected boom')
    end)
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_boom' } } } })

    local problem = resolved(bufnr, 'fake').problem
    assert.is_true(problem:find('failed to load', 1, true) ~= nil)
    assert.is_true(problem:find('unexpected boom', 1, true) ~= nil)
    assert.is_nil(problem:find('not on the runtimepath', 1, true))
  end)

  -- require() leaves its own sentinel in package.loaded once a chunk has
  -- raised, so a second query for the same module gets require()'s "loop or
  -- previous error" back rather than the original fault -- worth naming for
  -- what it is rather than surfacing that text verbatim.
  it('names a module that failed to load earlier, on a second query', function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_boom_twice', function()
      error('unexpected boom')
    end)
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_boom_twice' } } } })

    resolved(bufnr, 'fake')
    local problem = resolved(bufnr, 'fake').problem

    assert.is_true(problem:find('failed to load earlier', 1, true) ~= nil)
    assert.is_true(problem:find(':ZCmp reload', 1, true) ~= nil)
    assert.is_nil(problem:find('loop or previous error', 1, true))
  end)

  it("names the dependency, not this module, when a dependency's chunk raised earlier", function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_dep_boom', function()
      error('dep is misconfigured')
    end)
    helpers.stub(package.preload, 'zcmp_test_needs_dep', function()
      require('zcmp_test_dep_boom')
      return { completefunc = function() end }
    end)
    pcall(require, 'zcmp_test_dep_boom')
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_needs_dep' } } } })

    sources.resolve(bufnr)
    local problem = resolved(bufnr, 'fake').problem

    assert.is_true(problem:find('failed to load:', 1, true) ~= nil)
    assert.is_true(problem:find('zcmp_test_dep_boom', 1, true) ~= nil)
    assert.is_nil(problem:find('failed to load earlier', 1, true))
  end)

  it('reports a module that serves no matches', function()
    local bufnr = helpers.buffer()
    register('fake_source', {})
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    assert.is_true(resolved(bufnr, 'fake').problem:find('serves no matches', 1, true) ~= nil)
  end)

  -- source() answering nil is not "no source() at all" -- it is the answer,
  -- and reported on the same terms as any other non-string one.
  it('reports source() answering nil, not "neither source() nor completefunc()"', function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    local problem = resolved(bufnr, 'fake').problem
    assert.is_true(problem:find('source() answered nil', 1, true) ~= nil)
    assert.is_nil(problem:find('neither source() nor completefunc()', 1, true))
  end)

  -- A module with both takes source() -- completefunc() must not be reached
  -- as a fallback when source() answers nil.
  it('does not fall through to completefunc() when source() answers nil', function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() end, completefunc = function() end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    local problem = resolved(bufnr, 'fake').problem
    assert.is_true(problem:find('source() answered nil', 1, true) ~= nil)
  end)

  -- A provider module whose chunk forgets `return M` loads without error and
  -- pcall(require, ...) reports success -- module.enable/module.source would
  -- index a boolean otherwise.
  it("reports a module that returns nothing, and keeps the provider's flags", function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_no_return', function()
      return true
    end)
    config.setup({
      sources = {
        default = { 'fake' },
        providers = { fake = { flags = { '.' }, module = 'zcmp_test_no_return' } },
      },
    })

    local source = resolved(bufnr, 'fake')
    assert.is_true(source.problem:find('is not a table', 1, true) ~= nil)
    assert.are.equal('.', sources.resolve(bufnr))
  end)

  -- require() caches whatever a chunk that forgot `return M` returned
  -- (`true`), and :ZCmp status / :checkhealth zcmp reach such a module on
  -- every BufEnter and FileType through list(), the query path -- which must
  -- never re-run the chunk, only answer from what require() already cached.
  it("does not re-run a module's chunk on repeated queries, even when it forgot `return M`", function()
    local bufnr = helpers.buffer()
    local runs = 0
    helpers.stub(package.preload, 'zcmp_test_no_return_query', function()
      runs = runs + 1
      return true
    end)
    config.setup({
      sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_no_return_query' } } },
    })

    sources.list(bufnr)
    sources.list(bufnr)
    sources.list(bufnr)

    assert.are.equal(1, runs)
  end)

  -- require() caches whatever the chunk returned; a chunk that forgot
  -- `return M` is cached as `true` even after it is fixed on disk, unless
  -- the cache entry is dropped -- otherwise reload() would report the same
  -- stale "is not a table" forever. `:ZCmp status` and `:checkhealth zcmp`
  -- reach the module through list(), the query path, before any reload()
  -- does -- the cache must already be clear by then, or the first reload()
  -- after the fix would still need a second to take.
  it("recovers a module that forgot `return M`, once fixed and reset", function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_fix_me', function()
      return true
    end)
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_fix_me' } } } })

    assert.is_true(resolved(bufnr, 'fake').problem:find('is not a table', 1, true) ~= nil)

    helpers.stub(package.preload, 'zcmp_test_fix_me', function()
      return { completefunc = function() end }
    end)
    sources.reset()

    assert.are.equal([[Fv:lua.require'zcmp_test_fix_me'.completefunc]], sources.resolve(bufnr))
  end)

  -- The cache-drop is not "only a cached `true`" -- a chunk returning any
  -- other non-table is stuck the same way, and must recover the same way.
  it('recovers a module whose chunk returned a string, once fixed and reset', function()
    local bufnr = helpers.buffer()
    helpers.stub(package.preload, 'zcmp_test_fix_me_string', function()
      return 'x'
    end)
    config.setup({
      sources = { default = { 'fake' }, providers = { fake = { module = 'zcmp_test_fix_me_string' } } },
    })

    assert.is_true(resolved(bufnr, 'fake').problem:find('is not a table', 1, true) ~= nil)

    helpers.stub(package.preload, 'zcmp_test_fix_me_string', function()
      return { completefunc = function() end }
    end)
    sources.reset()

    assert.are.equal([[Fv:lua.require'zcmp_test_fix_me_string'.completefunc]], sources.resolve(bufnr))
  end)

  -- A leading empty entry in 'complete' is E539, which detaches the whole
  -- buffer -- an empty answer from source() must be treated like any other
  -- wrong-typed one, not written through.
  it("reports a module whose source() answers '', and keeps the provider's flags", function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() return '' end })
    config.setup({
      sources = { default = { 'fake' }, providers = { fake = { flags = { '.' }, module = 'fake_source' } } },
    })

    local source = resolved(bufnr, 'fake')
    assert.is_true(source.problem:find('serves no matches', 1, true) ~= nil)
    assert.are.equal('.', sources.resolve(bufnr))
  end)

  it('reports what a module answered when it is not a string at all', function()
    local bufnr = helpers.buffer()
    register('fake_source', { source = function() return { 'oops' } end })
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } } })

    local problem = resolved(bufnr, 'fake').problem
    assert.is_true(problem:find('source() answered', 1, true) ~= nil)
    assert.is_true(problem:find("not a 'complete' entry", 1, true) ~= nil)
    assert.is_nil(problem:find('neither source() nor completefunc()', 1, true))
  end)

  -- An empty flag written into 'complete' is the same E539 an empty source()
  -- answer is -- dropped rather than written through.
  it('drops an empty flag rather than writing it into complete', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'fake' }, providers = { fake = { flags = { '.', '' } } } } })

    assert.are.equal('.', sources.resolve(bufnr))
    assert.is_true(resolved(bufnr, 'fake').problem:find('empty entry', 1, true) ~= nil)
  end)

  it('keeps a provider flags when its module source() raises', function()
    local bufnr = helpers.buffer()
    register('fake_source', {
      source = function()
        error('boom')
      end,
    })
    config.setup({
      sources = { default = { 'fake' }, providers = { fake = { flags = { '.' }, module = 'fake_source' } } },
    })

    local source = resolved(bufnr, 'fake')
    assert.are.same({ '.' }, source.entries)
    assert.is_true(source.problem:find('source() raised', 1, true) ~= nil)
    assert.is_true(source.problem:find('boom', 1, true) ~= nil)
    assert.are.equal('.', sources.resolve(bufnr))
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

  -- attach_all() -- setup() with buffers already open, :ZCmp reload, a
  -- registration -- is exactly the path where the buffer being decided is
  -- not the one on screen; a no-argument predicate must still see it.
  it("runs a provider's `enabled` with the buffer being decided current", function()
    local lua_buf = helpers.buffer()
    vim.bo[lua_buf].filetype = 'lua'
    helpers.buffer() -- a second buffer, left current
    config.setup({
      sources = {
        default = { 'buffer' },
        providers = {
          buffer = {
            flags = { '.' },
            enabled = function()
              return vim.bo.filetype ~= 'lua'
            end,
          },
        },
      },
    })

    assert.are.equal('disabled', resolved(lua_buf, 'buffer').problem)
  end)

  it("runs a provider's `available` with the buffer being decided current", function()
    local lua_buf = helpers.buffer()
    vim.bo[lua_buf].filetype = 'lua'
    helpers.buffer() -- a second buffer, left current
    config.setup({
      sources = {
        default = { 'buffer' },
        providers = {
          buffer = {
            flags = { '.' },
            available = function()
              return vim.bo.filetype ~= 'lua'
            end,
          },
        },
      },
    })

    assert.are.equal('unavailable in this buffer', resolved(lua_buf, 'buffer').problem)
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
        providers = { half = { flags = { '.' }, module = 'no.such.module' } },
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

  -- The predicate's answer is read as a boolean, like `available`'s: a
  -- forgotten `return` is nil, not "enabled".
  it('treats an enabled() that returns nil as disabled', function()
    local bufnr = helpers.buffer()
    config.setup({
      sources = {
        default = { 'lsp' },
        providers = { lsp = { enabled = function() return nil end } },
      },
    })

    assert.is_nil(sources.provider(bufnr, 'lsp'))
  end)
end)

describe('sources.limit()', function()
  it('answers the default when opts is nil', function()
    assert.are.equal(10, sources.limit(nil, 10, 'path'))
  end)

  it('answers the default when opts.limit is nil', function()
    assert.are.equal(10, sources.limit({}, 10, 'path'))
  end)

  it('answers a whole number as itself', function()
    assert.are.equal(5, sources.limit({ limit = 5 }, 10, 'path'))
  end)

  it('rounds a fraction down and says so, the same as max_items', function()
    local answer
    local notified = helpers.notifications(function()
      answer = sources.limit({ limit = 1.5 }, 10, 'path')
    end)

    assert.are.equal(1, answer)
    assert.are.equal(1, #notified)
    assert.is_true(helpers.notified(notified, 'opts.limit should be a whole number, not 1.5'))
  end)

  -- A bad opts.limit would otherwise reach vim.fn.matchfuzzy() or a #items
  -- comparison and raise on every keystroke; the module's own default is the
  -- same fallback max_items's cap_suffix() makes for a bad number.
  for _, case in ipairs({ 0, -5, '10', math.huge }) do
    it(('falls back to the default and warns for %s'):format(vim.inspect(case)), function()
      local answer
      local notified = helpers.notifications(function()
        answer = sources.limit({ limit = case }, 10, 'path')
      end)

      assert.are.equal(10, answer)
      assert.is_true(helpers.notified(notified, 'opts.limit'))
    end)
  end
end)

describe('sources.trim_head()', function()
  -- What vim.lsp.completion's trigger() leaves: an item whose findstart was
  -- column 0 re-inserted at the keyword boundary after the `.`.
  local RELOCATED = 'console.console.log'

  -- The cursor sits after the last character, as in insert mode -- the only
  -- mode a CompleteDone handler runs in; Normal mode clamps it back one.
  before_each(function()
    helpers.stub(vim.o, 'virtualedit', 'onemore')
  end)
  after_each(function()
    vim.v.completed_item = vim.empty_dict()
  end)

  it('removes the head core left in front of a relocated word', function()
    helpers.buffer({ RELOCATED })
    vim.v.completed_item = { word = 'console.log', user_data = { zcmp_start = 0 } }

    assert.are.equal(8, sources.trim_head())
    assert.are.equal('console.log', vim.api.nvim_get_current_line())
    assert.are.same({ 1, 11 }, vim.api.nvim_win_get_cursor(0))
  end)

  -- The snippet core's accept() asks again with the item it was handed, so
  -- the two CompleteDone handlers need not agree on an order.
  it('is idempotent, and takes the item in place of v:completed_item', function()
    helpers.buffer({ RELOCATED })
    local item = { word = 'console.log', user_data = { zcmp_start = 0 } }

    assert.are.equal(8, sources.trim_head(item))
    assert.are.equal(0, sources.trim_head(item))
    assert.are.equal('console.log', vim.api.nvim_get_current_line())
    assert.are.same({ 1, 11 }, vim.api.nvim_win_get_cursor(0))
  end)

  it('leaves a word that sits at its own start alone', function()
    helpers.buffer({ 'console.log' })
    vim.v.completed_item = { word = 'console.log', user_data = { zcmp_start = 0 } }

    assert.are.equal(0, sources.trim_head())
    assert.are.equal('console.log', vim.api.nvim_get_current_line())
    assert.are.same({ 1, 11 }, vim.api.nvim_win_get_cursor(0))
  end)

  -- A cancel (<C-e>) puts the original text back; the word is then not
  -- under the cursor, and nothing ahead of it is ours to remove.
  it('leaves the line alone when the word is not at the cursor', function()
    helpers.buffer({ 'console.consolexlog' })
    vim.v.completed_item = { word = 'console.log', user_data = { zcmp_start = 0 } }

    assert.are.equal(0, sources.trim_head())
    assert.are.equal('console.consolexlog', vim.api.nvim_get_current_line())
  end)

  it('does nothing without a completed item', function()
    helpers.buffer({ RELOCATED })
    vim.v.completed_item = vim.empty_dict()

    assert.are.equal(0, sources.trim_head())
    assert.are.equal(RELOCATED, vim.api.nvim_get_current_line())
  end)

  -- The default provider, zsnip, records no start -- it cannot name ZCmp --
  -- and neither does a third party's module. Their items are put back when
  -- the text ahead of the word ends with the word's own head.
  describe('an item that records no start', function()
    -- The relocation this rule undoes can only come from vim.lsp.completion's
    -- restart, so these assume may_relocate() answers true; the cases where
    -- it answers false have their own tests below, using the real answer.
    before_each(function()
      helpers.stub(require('zcmp.lsp'), 'may_relocate', function()
        return true
      end)
    end)

    for _, case in ipairs({
      { line = RELOCATED, word = 'console.log', result = 'console.log' },
      { line = 'x<x<div', word = 'x<div', result = 'x<div' },
      { line = 'x ./sub/./sub/alpha.txt', word = './sub/alpha.txt', result = 'x ./sub/alpha.txt' },
    }) do
      it('is put back at its own head in ' .. case.line, function()
        helpers.buffer({ case.line })
        vim.v.completed_item = { word = case.word, user_data = { zsnip = { keep = 0 } } }

        assert.are.equal(#case.line - #case.result, sources.trim_head())
        assert.are.equal(case.result, vim.api.nvim_get_current_line())
        assert.are.same({ 1, #case.result }, vim.api.nvim_win_get_cursor(0))
      end)
    end

    -- The restart relocates to the `\k*$` boundary, so a head it skipped
    -- always holds a non-keyword character; one without is two words, as a
    -- buffer word accepted after itself is.
    it('leaves a head of keyword characters alone', function()
      helpers.buffer({ 'foofoo' })
      vim.v.completed_item = { word = 'foo' }

      assert.are.equal(0, sources.trim_head())
      assert.are.equal('foofoo', vim.api.nvim_get_current_line())
    end)

    -- The restart places the server's own items, so they are never
    -- relocated, and their words may carry punctuation: `print(...)` accepted
    -- inside a typed `print(` is nested, not put back. The mark is what tells
    -- the two apart; the same word without it is a keyless F source's.
    it('leaves a server item alone, and puts back the same word unmarked', function()
      helpers.buffer({ 'print(print(...)' })
      vim.v.completed_item = { word = 'print(...)', user_data = { nvim = { lsp = { completion_item = {} } } } }

      assert.are.equal(0, sources.trim_head())
      assert.are.equal('print(print(...)', vim.api.nvim_get_current_line())

      vim.v.completed_item = { word = 'print(...)' }

      assert.are.equal(6, sources.trim_head())
      assert.are.equal('print(...)', vim.api.nvim_get_current_line())
      assert.are.same({ 1, 10 }, vim.api.nvim_win_get_cursor(0))
    end)

    it('reads a wrongly typed start as none', function()
      helpers.buffer({ RELOCATED })
      vim.v.completed_item = { word = 'console.log', user_data = { zcmp_start = '0' } }

      assert.are.equal(8, sources.trim_head())
      assert.are.equal('console.log', vim.api.nvim_get_current_line())
    end)
  end)

  -- The text rule cannot tell "the restart relocated this item" from an F
  -- source whose own findstart merely sits behind a byte matching the
  -- word's head -- only the restart can have relocated anything, so with no
  -- client attached at all, nothing is trimmed.
  it('leaves a text-derived head alone with no LSP client attached', function()
    helpers.buffer({ RELOCATED })
    vim.v.completed_item = { word = 'console.log' }

    assert.are.equal(0, sources.trim_head())
    assert.are.equal(RELOCATED, vim.api.nvim_get_current_line())
  end)

  -- Attached is not, on its own, either of may_relocate()'s two routes: a
  -- server kept around for diagnostics or hover, with the buffer's source
  -- list naming no `lsp` provider (or the provider disabled) and no
  -- omnifunc entry in 'complete', never has lsp.sync() wire it and never
  -- restarts completion through vim.lsp.omnifunc -- so reading get_clients()
  -- alone, the bug the gate closes, would have trimmed a byte the user typed.
  describe('a client attached without being wired by zcmp', function()
    local function server(dispatchers)
      local closing = false
      return {
        request = function(method, _, callback)
          if method == 'initialize' then
            callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '.' } } } })
          elseif method == 'shutdown' then
            callback(nil, nil)
          end
          return true, 1
        end,
        notify = function(method)
          if method == 'exit' then
            dispatchers.on_exit(0, 15)
          end
          return true
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          closing = true
          dispatchers.on_exit(0, 15)
        end,
      }
    end

    after_each(function()
      for _, client in ipairs(vim.lsp.get_clients()) do
        client:stop()
      end
      vim.wait(2000, function()
        return #vim.lsp.get_clients() == 0
      end)
    end)

    it('leaves a text-derived head alone attached but not wired, and trims it once wired', function()
      local bufnr = helpers.buffer({ RELOCATED })
      local id = assert(vim.lsp.start({ name = 'zcmp-test', cmd = server }, { bufnr = bufnr }))
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
      end)
      local client = assert(vim.lsp.get_client_by_id(id))

      vim.v.completed_item = { word = 'console.log' }
      assert.are.equal(0, sources.trim_head())
      assert.are.equal(RELOCATED, vim.api.nvim_get_current_line())

      -- Same buffer, same line and cursor -- the gate is the only thing
      -- that changed between the two calls.
      assert.is_true(require('zcmp.lsp').attach(client, bufnr, {}))
      vim.v.completed_item = { word = 'console.log' }
      assert.are.equal(8, sources.trim_head())
      assert.are.equal('console.log', vim.api.nvim_get_current_line())
    end)

    -- Route 2: vim.lsp.completion's own M._omnifunc() calls trigger()
    -- directly, with no buf_handles lookup -- unlike M.get(), it never asks
    -- whether zcmp (or anyone) called enable() -- so the restart relocates
    -- even with wired empty, as long as the `lsp` provider's entry sits in
    -- 'complete' and a completion-capable client is attached. Reachable
    -- with the shipped `zcmp.lsp` module under any provider id, not only
    -- `lsp`, which is exactly what this reproduces.
    it("trims with the entry in 'complete' and a client attached, even unwired", function()
      config.setup({
        sources = { default = { 'other' }, providers = { other = { module = 'zcmp.lsp' } } },
      })
      local bufnr = helpers.buffer({ RELOCATED })
      vim.bo[bufnr].complete = sources.resolve(bufnr)
      assert(vim.lsp.start({ name = 'zcmp-test', cmd = server }, { bufnr = bufnr }))
      vim.wait(2000, function()
        return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
      end)

      vim.v.completed_item = { word = 'console.log' }
      assert.are.equal(8, sources.trim_head())
      assert.are.equal('console.log', vim.api.nvim_get_current_line())
    end)
  end)

  -- The text cannot tell that `cnsl.` was `console.` typed fuzzily; the
  -- recorded start can.
  it('trims a fuzzily typed head only from the recorded start', function()
    helpers.buffer({ 'cnsl.console.log' })
    vim.v.completed_item = { word = 'console.log' }
    assert.are.equal(0, sources.trim_head())
    assert.are.equal('cnsl.console.log', vim.api.nvim_get_current_line())

    vim.v.completed_item = { word = 'console.log', user_data = { zcmp_start = 0 } }
    assert.are.equal(5, sources.trim_head())
    assert.are.equal('console.log', vim.api.nvim_get_current_line())
    assert.are.same({ 1, 11 }, vim.api.nvim_win_get_cursor(0))
  end)
end)
