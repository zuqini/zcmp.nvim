local commands = require('zcmp.commands')
local helpers = require('helpers')

---@return boolean
local function exists()
  return vim.fn.exists(':ZCmp') == 2
end

before_each(helpers.reset)
after_each(helpers.cleanup)

describe(':ZCmp', function()
  it('is created by setup(), and can be taken away again', function()
    assert.is_false(exists())

    require('zcmp').setup({})
    assert.is_true(exists())

    commands.remove()
    assert.is_false(exists())
  end)

  it('reports an unknown subcommand', function()
    require('zcmp').setup({})

    local notified = helpers.notifications(function()
      vim.cmd('ZCmp nonsense')
    end)

    assert.is_true(helpers.notified(notified, 'unknown subcommand'))
  end)

  it('completes its subcommands', function()
    require('zcmp').setup({})
    local completions = vim.fn.getcompletion('ZCmp ', 'cmdline')

    assert.contains(completions, 'status')
    assert.contains(completions, 'reload')
  end)

  it('turns completion off and back on', function()
    require('zcmp').setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    vim.cmd('ZCmp disable')
    assert.is_false(require('zcmp').is_enabled())
    assert.is_false(require('zcmp.buffer').attached(bufnr))

    vim.cmd('ZCmp enable')
    helpers.settle(bufnr)
    assert.is_true(require('zcmp').is_enabled())
    assert.is_true(require('zcmp.buffer').attached(bufnr))
  end)

  -- A provider module installed after startup: reload is what picks it up.
  it('starts a provider module that has arrived since', function()
    local started = 0
    helpers.stub(package.loaded, 'fake_source', {
      completefunc = function() end,
      enable = function()
        started = started + 1
      end,
    })
    require('zcmp').setup({
      sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } },
    })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)
    assert.are.equal(1, started)

    vim.cmd('ZCmp reload')
    helpers.settle(bufnr)
    assert.are.equal(2, started)
  end)
end)

describe(':ZCmp status', function()
  it('names each source, and what it contributes', function()
    require('zcmp').setup({ sources = { default = { 'buffer', 'snippets' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    local status = table.concat(commands.status(bufnr), '\n')

    assert.is_true(status:find('ZCmp.nvim ' .. require('zcmp').version, 1, true) ~= nil)
    assert.is_true(status:find('attached', 1, true) ~= nil)
    assert.is_true(status:find('.^100,w^100,b^100', 1, true) ~= nil)
    assert.is_true(status:find('zsnip.complete', 1, true) ~= nil)
  end)

  it('lists the keys it installed', function()
    require('zcmp').setup({ keymap = { preset = 'enter' } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    assert.is_true(table.concat(commands.status(bufnr), '\n'):find('i:<CR>', 1, true) ~= nil)
  end)

  -- 'autocomplete' is global-local, so `vim.bo[bufnr].autocomplete` -- the
  -- local slot alone -- is nil in a buffer zcmp never attached to, even
  -- though 'set autocomplete?' would report the global value there.
  it("reports the effective 'autocomplete' in a buffer it does not drive", function()
    require('zcmp').setup({})
    local bufnr = helpers.buffer()
    vim.bo[bufnr].buftype = 'nofile'
    helpers.settle(bufnr)

    assert.is_false(require('zcmp.buffer').attached(bufnr))
    assert.is_true(table.concat(commands.status(bufnr), '\n'):find("'autocomplete' false", 1, true) ~= nil)
  end)

  -- 'completeopt' is global-local too: reading `vim.o.completeopt` outside
  -- the `bufnr` nvim_buf_call reports whichever buffer is current when
  -- status() runs, not the one it was asked about.
  it("reports 'completeopt' for the buffer asked about, not the current one", function()
    require('zcmp').setup({})
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    local other = helpers.buffer()
    vim.bo[other].completeopt = 'menu'
    vim.api.nvim_set_current_buf(other)

    local status = table.concat(commands.status(bufnr), '\n')
    assert.is_true(status:find("'completeopt' " .. require('zcmp.buffer').completeopt(), 1, true) ~= nil)
  end)
end)
