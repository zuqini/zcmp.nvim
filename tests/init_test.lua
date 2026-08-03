local buffer = require('zcmp.buffer')
local config = require('zcmp.config')
local helpers = require('helpers')
local keymap = require('zcmp.keymap')
local zcmp = require('zcmp')

---@param bufnr integer
---@return string[]
local function keys(bufnr)
  return vim.tbl_map(function(key)
    return key.lhs
  end, keymap.installed(bufnr))
end

before_each(helpers.reset)
after_each(helpers.cleanup)

describe('the autocmds', function()
  -- `sources.per_filetype` is keyed off a buffer option that BufEnter does not
  -- wait for: `:enew` then `:setfiletype` never re-derived anything.
  it('re-derive the source list when the filetype arrives late', function()
    zcmp.setup({
      sources = {
        default = { 'buffer' },
        per_filetype = { markdown = { 'path' } },
      },
    })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)

    vim.bo[bufnr].filetype = 'markdown'
    vim.wait(200, function()
      return vim.bo[bufnr].complete ~= '.^100,w^100,b^100'
    end)

    assert.are.equal(require('zcmp.sources.path').source(), vim.bo[bufnr].complete)
  end)

  -- Nothing else drops a buffer's entry, and `attached(bufnr)` answering true
  -- for a handle that no longer exists is what the reporters read.
  it('forget a buffer that has been wiped out', function()
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)
    assert.is_true(buffer.attached(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.wait(100)

    assert.is_false(buffer.attached(bufnr))
    assert.are.same({}, keymap.installed(bufnr))
  end)
end)

describe('a second setup()', function()
  -- wire() leaves the mappings of a buffer it has already attached alone, so
  -- the keys stayed on the first preset while 'complete' moved to the second.
  it('re-derives the mappings as well as the options', function()
    zcmp.setup({ keymap = { preset = 'default' }, sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)
    assert.is_not.contains(keys(bufnr), '<CR>')

    zcmp.setup({ keymap = { preset = 'enter' }, sources = { default = { 'path' } } })
    helpers.settle(bufnr)

    assert.contains(keys(bufnr), '<CR>')
    assert.are.equal(require('zcmp.sources.path').source(), vim.bo[bufnr].complete)
  end)

  -- setup() replaces the resolved options wholesale, a provider's `opts` with
  -- them -- but a module started from the first set was remembered as started,
  -- so it went on holding options the second setup() had already replaced.
  it('offers a provider module the opts it has just resolved', function()
    local started = {}
    helpers.stub(package.loaded, 'fake_source', {
      completefunc = function() end,
      enable = function(opts)
        started[#started + 1] = opts
      end,
    })
    local function setup(limit)
      zcmp.setup({
        sources = {
          default = { 'fake' },
          providers = { fake = { module = 'fake_source', opts = { limit = limit } } },
        },
      })
    end

    setup(1)
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)
    setup(2)
    helpers.settle(bufnr)

    assert.are.same({ { limit = 1 }, { limit = 2 } }, started)
  end)
end)

describe('registering a source', function()
  it('takes effect in a buffer that is already attached', function()
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    zcmp.add_source_provider('spell', { flags = { 'kspell' } })
    zcmp.add_filetype_source(vim.bo[bufnr].filetype, 'spell')
    vim.wait(200, function()
      return vim.bo[bufnr].complete:find('kspell', 1, true) ~= nil
    end)

    assert.are.equal('.^100,w^100,b^100,kspell', vim.bo[bufnr].complete)
  end)

  -- A plugin registering a source from its own config block runs before the
  -- user's setup() as often as after, and setup() replaces `options`.
  it('survives a setup() that runs afterwards', function()
    zcmp.add_source_provider('spell', { flags = { 'kspell' } })
    zcmp.setup({ sources = { default = { 'spell' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    assert.are.equal('kspell', vim.bo[bufnr].complete)
  end)
end)

describe('disable()', function()
  it('leaves nothing of its own behind', function()
    local completeopt = vim.go.completeopt
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    local complete = vim.bo[bufnr].complete
    helpers.settle(bufnr)
    assert.are_not.equal(completeopt, vim.go.completeopt)

    zcmp.disable()

    assert.is_false(zcmp.is_enabled())
    assert.are.equal(complete, vim.bo[bufnr].complete)
    assert.are.equal(completeopt, vim.go.completeopt)
    assert.are.same({}, keymap.installed(bufnr))
    -- The group is gone, not merely empty: asking for one that does not exist
    -- is what raises.
    assert.is_false((pcall(vim.api.nvim_get_autocmds, { group = 'zcmp' })))
  end)

  -- attach() schedules and disable() does not, so a pass issued in the same
  -- tick used to land afterwards and wire the buffer back up.
  it('is not undone by a pass already in the scheduler', function()
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    zcmp.disable()
    vim.wait(100)

    assert.is_false(zcmp.is_enabled())
    assert.is_false(buffer.attached(bufnr))
    assert.are.same({}, keymap.installed(bufnr))
  end)
end)

describe('reload()', function()
  it('keeps driving the buffers it was driving', function()
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    zcmp.reload()
    helpers.settle(bufnr)

    assert.is_true(buffer.attached(bufnr))
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
    assert.is_true(#keymap.installed(bufnr) > 0)
  end)

  -- `:ZCmp disable` then `:ZCmp reload` used to map the keys and write
  -- 'complete' again, with the autocmds gone and is_enabled() saying false --
  -- a state nothing else could produce and nothing was left to maintain.
  it('takes nothing back while the plugin is disabled', function()
    zcmp.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    local original = vim.bo[bufnr].complete
    helpers.settle(bufnr)
    assert.are_not.equal(original, vim.bo[bufnr].complete)

    zcmp.disable()
    zcmp.reload()
    vim.wait(100)

    assert.is_false(zcmp.is_enabled())
    assert.is_false(buffer.attached(bufnr))
    assert.are.same({}, keymap.installed(bufnr))
    assert.are.equal(original, vim.bo[bufnr].complete)
  end)
end)

-- The first thing enable() reads is an option an older Neovim does not have,
-- and an unknown-option traceback out of a buffer module names nothing a user
-- can act on.
describe('the version floor', function()
  it('wires nothing below it, and says why', function()
    local has = vim.fn.has
    helpers.stub(vim.fn, 'has', function(feature)
      return feature == 'nvim-0.12' and 0 or has(feature)
    end)
    local bufnr = helpers.buffer()
    local complete = vim.bo[bufnr].complete

    local notified = helpers.notifications(function()
      zcmp.setup({ sources = { default = { 'buffer' } } })
    end)
    vim.wait(100)

    assert.is_true(helpers.notified(notified, 'Neovim 0.12.0+ is required'))
    assert.is_false(zcmp.is_enabled())
    assert.is_false(buffer.attached(bufnr))
    assert.are.equal(complete, vim.bo[bufnr].complete)
    assert.are.same({}, keymap.installed(bufnr))
  end)
end)

describe('the command surface', function()
  it('re-exports every command zcmp.api has', function()
    local api = require('zcmp.api')
    for name, value in pairs(api) do
      if type(value) == 'function' then
        assert.are.equal(value, zcmp[name], ('zcmp.%s is not re-exported'):format(name))
      end
    end
  end)

  it('keeps the predicates out of the keymap commands', function()
    local api = require('zcmp.api')
    for name in pairs(api.predicates) do
      assert.is_function(api[name], ('%s is not an api function'):format(name))
    end
    assert.is_nil(config.options.keymap[next(api.predicates)])
  end)
end)
