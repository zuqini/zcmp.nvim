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
    -- releases. `noselect` is written even though 'autocomplete' forces it:
    -- the menu vim.lsp.completion rebuilds through vim.fn.complete() does not.
    local expected = 'menuone,fuzzy,popup,noinsert,noselect'
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
    assert.is_not_nil(buffer.completeopt():find('noselect'))
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
    assert.are.equal(0, vim.go.autocompletedelay)
    assert.are.equal(buffer.completeopt(), vim.go.completeopt)
    assert.is_not_nil(vim.go.shortmess:find('c', 1, true))
  end)

  it('puts back what it found', function()
    local outer = vim.go.autocompletedelay
    local before = { completeopt = vim.go.completeopt, delay = 200 }
    vim.go.autocompletedelay = before.delay
    config.setup({})

    buffer.apply_globals()
    assert.are.equal(0, vim.go.autocompletedelay)

    buffer.restore_globals()
    assert.are.equal(before.completeopt, vim.go.completeopt)
    assert.are.equal(before.delay, vim.go.autocompletedelay)
    vim.go.autocompletedelay = outer
  end)
end)

describe("'autocompletedelay'", function()
  -- Held at 0 whatever it was, and with no option to raise it: any non-zero
  -- value lets vim.lsp.completion open the menu through vim.fn.complete()
  -- before core has scanned 'complete', and core never scans it again for the
  -- rest of that cycle. See buffer.apply_globals().
  it('overrides a non-zero value the user set themselves', function()
    vim.go.autocompletedelay = 500
    config.setup({})

    buffer.apply_globals()

    assert.are.equal(0, vim.go.autocompletedelay)
  end)

  it('reports the removed option rather than calling it unknown', function()
    local notified = helpers.notifications(function()
      config.setup({ completion = { menu = { auto_show_delay_ms = 200 } } })
    end)

    assert.is_true(helpers.notified(notified, 'auto_show_delay_ms has been removed'))
    assert.is_false(helpers.notified(notified, 'unknown option'))
  end)

  it('keeps 0 even when the removed option asked for a delay', function()
    helpers.notifications(function()
      config.setup({ completion = { menu = { auto_show_delay_ms = 200 } } })
      buffer.apply_globals()
    end)

    assert.are.equal(0, vim.go.autocompletedelay)
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

  -- attach_all() -- setup() with buffers already open, :ZCmp reload, a
  -- registration -- is exactly the path where the buffer being decided is
  -- not the one on screen; a no-argument predicate must still see it.
  it('runs `enabled` with the buffer being decided current, not whichever one is on screen', function()
    config.setup({
      enabled = function()
        return vim.bo.filetype ~= 'lua'
      end,
      sources = { default = { 'buffer' } },
    })
    local lua_buf = helpers.buffer()
    vim.bo[lua_buf].filetype = 'lua'
    helpers.buffer() -- a second buffer, left current

    buffer.attach(lua_buf)
    vim.wait(100)

    assert.is_false(buffer.attached(lua_buf))
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

  -- :bdelete fires LspDetach before BufDelete: the pass LspDetach schedules
  -- lands after the detach, on a buffer that is still valid but unloaded.
  it('does not take back a buffer that was unloaded before the schedule ran', function()
    config.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    buffer.attach(bufnr)
    vim.wait(100)
    assert.is_true(buffer.attached(bufnr))

    buffer.attach(bufnr)
    vim.api.nvim_set_current_buf(helpers.buffer())
    vim.api.nvim_buf_delete(bufnr, { unload = true, force = true })
    buffer.detach(bufnr)
    vim.wait(100)

    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    assert.is_false(vim.api.nvim_buf_is_loaded(bufnr))
    assert.is_false(buffer.attached(bufnr))
  end)

  -- attach() schedules; detach_all() does not. Without a generation to check,
  -- the pending pass put back everything disable() had just taken.
  it('drops a pass that was scheduled before everything was detached', function()
    config.setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()

    buffer.attach(bufnr)
    buffer.detach_all()
    vim.wait(100)

    assert.is_false(buffer.attached(bufnr))
    assert.are.same({}, keymap.installed(bufnr))
    assert.is_not_true(vim.bo[bufnr].autocomplete)
  end)

  -- 'complete' raises rather than ignoring what it does not understand, and
  -- the value is assembled out of other people's config.
  it('gives a buffer back rather than leaving it half-wired', function()
    config.setup({
      sources = { default = { 'bad' }, providers = { bad = { flags = { 'not a flag' } } } },
    })
    local bufnr = helpers.buffer()
    local before = vim.bo[bufnr].complete

    local notified = helpers.notifications(function()
      buffer.attach(bufnr)
      vim.wait(100)
    end)

    assert.is_false(buffer.attached(bufnr))
    assert.are.equal(before, vim.bo[bufnr].complete)
    assert.are.same({}, keymap.installed(bufnr))
    assert.is_true(helpers.notified(notified, "'complete' would not take"))
  end)

  it('gives a buffer back when keymap.apply raises', function()
    config.setup({})
    local bufnr = helpers.buffer()
    local before = { complete = vim.bo[bufnr].complete, autocomplete = vim.bo[bufnr].autocomplete }
    helpers.stub(keymap, 'apply', function()
      error('boom')
    end)

    local notified = helpers.notifications(function()
      buffer.attach(bufnr)
      vim.wait(100)
    end)

    assert.is_false(buffer.attached(bufnr))
    assert.are.equal(before.complete, vim.bo[bufnr].complete)
    assert.are.equal(before.autocomplete, vim.bo[bufnr].autocomplete)
    assert.is_true(helpers.notified(notified, 'keymap.apply raised'))
  end)

  it('reports an `enabled` that raises rather than doing so on every BufEnter', function()
    config.setup({
      enabled = function()
        error('no')
      end,
    })
    local bufnr = helpers.buffer()

    local notified = helpers.notifications(function()
      buffer.attach(bufnr)
      vim.wait(100)
    end)

    assert.is_false(buffer.attached(bufnr))
    assert.is_true(helpers.notified(notified, 'the `enabled` option raised'))
  end)
end)
