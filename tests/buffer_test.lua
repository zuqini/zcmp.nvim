local buffer = require('zcmp.buffer')
local config = require('zcmp.config')
local helpers = require('helpers')
local keymap = require('zcmp.keymap')

before_each(helpers.reset)
after_each(helpers.cleanup)

describe("'completeopt'", function()
  it('asks for a preselected, uninserted, fuzzy menu with a popup', function()
    config.setup({})

    -- `preselect` is newer than the 0.12.0 floor; the rest has been there for
    -- releases.
    local expected = 'menuone,fuzzy,popup,noinsert'
    assert.are.equal(buffer.can_preselect() and expected .. ',preselect' or expected, buffer.completeopt())
  end)

  it('drops the popup when documentation is off', function()
    config.setup({ completion = { documentation = { auto_show = false } } })

    assert.is_nil(buffer.completeopt():find('popup'))
  end)

  it('drops noinsert when the selection is auto-inserted', function()
    config.setup({ completion = { list = { selection = { auto_insert = true } } } })

    assert.is_nil(buffer.completeopt():find('noinsert'))
  end)

  it('drops preselect when nothing should be selected', function()
    config.setup({ completion = { list = { selection = { preselect = false } } } })

    assert.is_nil(buffer.completeopt():find('preselect'))
  end)

  it('drops fuzzy when fuzzy matching is off', function()
    config.setup({ fuzzy = { enabled = false } })

    assert.is_nil(buffer.completeopt():find('fuzzy'))
  end)

  -- The option raises E474 rather than ignoring a flag it does not know, and
  -- `preselect` is newer than the version floor.
  it('asks only for flags this Neovim understands', function()
    config.setup({})
    local saved = vim.go.completeopt

    assert.has_no.errors(function()
      vim.go.completeopt = buffer.completeopt()
    end)
    vim.go.completeopt = saved
  end)
end)

describe('global options', function()
  it("takes 'autocomplete' global-off so that attaching is what turns it on", function()
    config.setup({})
    buffer.apply_globals()

    assert.is_false(vim.go.autocomplete)
    assert.are.equal(200, vim.go.autocompletedelay)
    assert.are.equal(buffer.completeopt(), vim.go.completeopt)
    assert.is_not_nil(vim.go.shortmess:find('c', 1, true))
  end)

  it('puts back what it found', function()
    local before = { completeopt = vim.go.completeopt, delay = vim.go.autocompletedelay }
    config.setup({ completion = { trigger = { delay_ms = 50 } } })

    buffer.apply_globals()
    assert.are.equal(50, vim.go.autocompletedelay)

    buffer.restore_globals()
    assert.are.equal(before.completeopt, vim.go.completeopt)
    assert.are.equal(before.delay, vim.go.autocompletedelay)
  end)
end)

describe('attaching', function()
  it('drives an ordinary buffer', function()
    config.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    buffer.attach(bufnr)
    helpers.settle(bufnr)

    assert.is_true(buffer.attached(bufnr))
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
    assert.is_true(vim.bo[bufnr].autocomplete)
    assert.is_true(#keymap.installed(bufnr) > 0)
  end)

  -- A prompt or terminal buffer keeps core's own menu, and its own keys.
  it('leaves a buffer the enabled check rejects alone', function()
    config.setup({})
    local scratch = vim.api.nvim_create_buf(false, true)
    local before = vim.bo[scratch].complete

    buffer.attach(scratch)
    vim.wait(100)

    assert.is_false(buffer.attached(scratch))
    assert.are.equal(before, vim.bo[scratch].complete)
    assert.are.same({}, keymap.installed(scratch))
  end)

  it('takes the enabled check from the config', function()
    config.setup({
      enabled = function()
        return false
      end,
    })
    local bufnr = helpers.buffer()

    buffer.attach(bufnr)
    vim.wait(100)
    assert.is_false(buffer.attached(bufnr))
  end)

  -- The single writer of 'complete': every pass derives the whole value, so a
  -- second one cannot append a second copy of anything.
  it('re-derives the option rather than adding to it', function()
    config.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()

    buffer.attach(bufnr)
    helpers.settle(bufnr)
    buffer.attach(bufnr)
    vim.wait(100)

    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)

  it('gives the buffer back what it had', function()
    config.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    local before = vim.bo[bufnr].complete

    buffer.attach(bufnr)
    helpers.settle(bufnr)
    buffer.detach(bufnr)

    assert.is_false(buffer.attached(bufnr))
    assert.are.equal(before, vim.bo[bufnr].complete)
    assert.are.same({}, keymap.installed(bufnr))
  end)

  it('detaches a buffer the enabled check has stopped accepting', function()
    local drive = true
    config.setup({
      enabled = function()
        return drive
      end,
      sources = { default = { 'buffer' } },
    })
    local bufnr = helpers.buffer()

    buffer.attach(bufnr)
    helpers.settle(bufnr)
    assert.is_true(buffer.attached(bufnr))

    drive = false
    buffer.attach(bufnr)
    vim.wait(100, function()
      return not buffer.attached(bufnr)
    end)
    assert.is_false(buffer.attached(bufnr))
  end)

  it('picks up a buffer that was open before setup ran', function()
    local bufnr = helpers.buffer()
    config.setup({ sources = { default = { 'buffer' } } })

    buffer.attach_all()
    helpers.settle(bufnr)

    assert.is_true(buffer.attached(bufnr))
  end)

  it('survives a buffer that is deleted before the schedule runs', function()
    config.setup({})
    local bufnr = helpers.buffer()

    buffer.attach(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.wait(100)

    assert.is_false(buffer.attached(bufnr))
  end)
end)
