local config = require('zcmp.config')
local helpers = require('helpers')
local lsp = require('zcmp.lsp')

---An in-process language server that answers completion, so that the LSP hook
---can be exercised without a binary to talk to.
---@param dispatchers vim.lsp.rpc.Dispatchers
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

---@param bufnr integer
---@return vim.lsp.Client
local function start(bufnr)
  local id = assert(vim.lsp.start({ name = 'zcmp-test', cmd = server }, { bufnr = bufnr }))
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
  end)
  return assert(vim.lsp.get_client_by_id(id))
end

---vim.lsp.completion has no "is it on" to ask. Its autotrigger is an
---InsertCharPre autocmd on the buffer, and nothing else installs one here.
---@param bufnr integer
---@return integer
local function autotriggers(bufnr)
  return #vim.api.nvim_get_autocmds({ event = 'InsertCharPre', buffer = bufnr })
end

local function stop()
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop()
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients() == 0
  end)
end

before_each(helpers.reset)
after_each(function()
  stop()
  helpers.cleanup()
end)

describe('trigger characters', function()
  it('widens the list to every letter, so a plain keyword re-asks', function()
    local client = { server_capabilities = { completionProvider = { triggerCharacters = { '.', ':' } } } }

    local chars = lsp.trigger_characters(client)
    assert.contains(chars, '.')
    assert.contains(chars, ':')
    assert.contains(chars, 'a')
    assert.contains(chars, 'Z')
  end)

  -- setup() runs again on every LspAttach, and a server may re-announce.
  it('is idempotent', function()
    local client = { server_capabilities = { completionProvider = { triggerCharacters = { 'a', '.' } } } }

    client.server_capabilities.completionProvider.triggerCharacters = lsp.trigger_characters(client)
    local twice = lsp.trigger_characters(client)

    assert.are.equal(53, #twice)
  end)

  it('copes with a server that declares none', function()
    local client = { server_capabilities = { completionProvider = {} } }

    assert.are.equal(52, #lsp.trigger_characters(client))
  end)
end)

describe('capabilities', function()
  it("are core's, with an override merged in", function()
    local capabilities = lsp.capabilities({ textDocument = { completion = { dynamicRegistration = true } } })

    assert.is_true(capabilities.textDocument.completion.dynamicRegistration)
    assert.is_not_nil(capabilities.textDocument.hover)
  end)

  -- blink.cmp's own second argument: `false` skips Neovim's own defaults
  -- entirely, rather than merging the override over them.
  it('answers only the override when include_nvim_defaults is false', function()
    local capabilities = lsp.capabilities({ textDocument = { completion = { dynamicRegistration = true } } }, false)

    assert.is_true(capabilities.textDocument.completion.dynamicRegistration)
    assert.is_nil(capabilities.textDocument.hover)
  end)
end)

describe('attaching a client', function()
  it('declines a server that does not complete', function()
    local client = {
      server_capabilities = {},
      supports_method = function()
        return false
      end,
    }

    assert.is_false(lsp.attach(client, 0))
  end)

  -- Off-spec (the field should be an object or absent), or missing outright
  -- while `supports_method` still answers true (dynamic registration) --
  -- either way there is nothing to index, so it is wired the same as a
  -- client whose server declared no trigger characters, not declined:
  -- declining left it out of `wired`, so every M.sync() pass saw it as
  -- never wired and churned every other client of the buffer on each pass.
  it('wires a server answering completionProvider: true, rather than declining it', function()
    local client = {
      id = -1,
      server_capabilities = { completionProvider = true },
      supports_method = function()
        return true
      end,
    }
    helpers.stub(vim.lsp.completion, 'enable', function() end)

    assert.is_true(lsp.attach(client, 0))
  end)

  -- The empty table M.attach() substitutes for a non-table completionProvider
  -- must not stick once nothing needs it any more, the same as the
  -- triggerCharacters it carries.
  it("forget() puts completionProvider back to true once the substituted table is no longer needed", function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)
    client.server_capabilities.completionProvider = true
    helpers.stub(vim.lsp.completion, 'enable', function() end)

    assert.is_true(lsp.attach(client, bufnr))
    assert.are.equal('table', type(client.server_capabilities.completionProvider))

    lsp.forget(bufnr, client.id)

    assert.is_true(client.server_capabilities.completionProvider)
  end)

  -- Substituting a table exists only to hold a widened triggerCharacters
  -- list; with widening off there is nothing for it to hold, so a non-table
  -- completionProvider must be left exactly as the server declared it.
  it('leaves completionProvider: true untouched when extend_trigger_characters is false', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)
    client.server_capabilities.completionProvider = true
    helpers.stub(vim.lsp.completion, 'enable', function() end)

    assert.is_true(lsp.attach(client, bufnr, { extend_trigger_characters = false }))
    assert.is_true(client.server_capabilities.completionProvider)

    lsp.forget(bufnr, client.id)

    assert.is_true(client.server_capabilities.completionProvider)
  end)

  -- The autotrigger opens the menu on its own, so `auto_show = false` has to
  -- reach it as well as 'autocomplete': with only the provider's own opt
  -- consulted, the menu still opened as you typed, from the server alone.
  describe('hands vim.lsp.completion an autotrigger that is', function()
    ---@param setup_opts table
    ---@param provider_opts table
    ---@return boolean
    local function autotrigger(setup_opts, provider_opts)
      config.setup(setup_opts)
      local client = {
        id = -1,
        server_capabilities = { completionProvider = { triggerCharacters = {} } },
        supports_method = function()
          return true
        end,
      }
      local passed
      helpers.stub(vim.lsp.completion, 'enable', function(_, _, _, opts)
        passed = opts
      end)

      assert.is_true(lsp.attach(client, 0, provider_opts))
      return passed.autotrigger
    end

    it('off when completion.menu.auto_show is off', function()
      assert.is_false(autotrigger({ completion = { menu = { auto_show = false } } }, { autotrigger = true }))
    end)

    it("off when the provider's own opt is off", function()
      assert.is_false(autotrigger({ completion = { menu = { auto_show = true } } }, { autotrigger = false }))
    end)

    it('on when both allow it', function()
      assert.is_true(autotrigger({ completion = { menu = { auto_show = true } } }, { autotrigger = true }))
    end)
  end)

  it('reports no server to ask in a buffer with none', function()
    assert.is_false(lsp.available(helpers.buffer()))
  end)

  -- A client that stopped between get_clients() and this scheduled call is
  -- an invalid id vim.lsp.completion.enable() asserts on -- see the comment
  -- above the pcall in M.attach().
  it('restores triggerCharacters and wires nothing when enable() raises', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)
    local original = client.server_capabilities.completionProvider.triggerCharacters
    client:stop()
    vim.wait(2000, function()
      return vim.lsp.get_client_by_id(client.id) == nil
    end)

    assert.is_false(lsp.attach(client, bufnr))
    assert.are.same(original, client.server_capabilities.completionProvider.triggerCharacters)

    local calls = {}
    helpers.stub(vim.lsp.completion, 'enable', function(enable, client_id, buf)
      calls[#calls + 1] = { enable, client_id, buf }
    end)
    -- If M.attach() had recorded the client as wired despite the failure,
    -- this would find it stale and try to unwire it.
    lsp.sync(bufnr, nil)

    assert.are.same({}, calls)
  end)

  it('wires a real client up, and puts the omnifunc in complete', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return vim.bo[bufnr].complete:find('Fv:lua.vim.lsp.omnifunc,', 1, true) ~= nil
    end)

    assert.is_true(lsp.available(bufnr))
    assert.are.equal('Fv:lua.vim.lsp.omnifunc,.^100,w^100,b^100', vim.bo[bufnr].complete)
    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')
  end)

  -- Declining a `completionProvider: true` client left it out of `wired`,
  -- so it read as unwired on every sync() pass and was dropped and
  -- re-enabled on each one -- would fire on every BufEnter/FileType/
  -- LspAttach in steady state, not just once.
  it('does not keep re-wiring a client whose completionProvider is true rather than a table', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)
    client.server_capabilities.completionProvider = true

    local calls = {}
    helpers.stub(vim.lsp.completion, 'enable', function(enable, client_id, buf)
      calls[#calls + 1] = { enable, client_id, buf }
    end)

    -- The client was never wired, so this pass takes the usual reclaim
    -- route -- drop, then re-enable -- exactly as it would for a table
    -- provider; the bug was every *subsequent* pass repeating it.
    lsp.sync(bufnr, { opts = {} })
    assert.are.same({ false, client.id, bufnr }, calls[1])
    assert.are.same({ true, client.id, bufnr }, calls[2])

    lsp.sync(bufnr, { opts = {} })
    assert.are.equal(2, #calls)
  end)

  it('leaves the omnifunc out again once the last client goes', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    start(bufnr)
    vim.wait(500, function()
      return vim.bo[bufnr].complete:find('Fv:lua.vim.lsp.omnifunc,', 1, true) ~= nil
    end)

    stop()
    vim.wait(500, function()
      return vim.bo[bufnr].complete == '.^100,w^100,b^100'
    end)
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)

  -- The one thing disable() exists to stop was the only thing surviving it:
  -- core's InsertCharPre hook stayed installed and every letter still opened
  -- the menu, in a buffer whose 'complete' and mappings had all been given
  -- back.
  it('switches vim.lsp.completion back off, and puts the trigger list back', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return vim.bo[bufnr].complete:find('Fv:lua.vim.lsp.omnifunc,', 1, true) ~= nil
    end)
    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')
    assert.are.equal(1, autotriggers(bufnr))

    require('zcmp').disable()

    assert.are.equal(0, autotriggers(bufnr))
    assert.are.same({ '.' }, client.server_capabilities.completionProvider.triggerCharacters)
  end)

  -- A buffer ZCmp declines to drive must not get vim.lsp.completion either:
  -- the widened trigger list lives on the client, so it leaks out of the
  -- buffer that widened it into every other one that client serves.
  it('leaves a client alone in a buffer the enabled check rejects', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({
      enabled = function()
        return false
      end,
      sources = { default = { 'lsp', 'buffer' } },
    })

    local client = start(bufnr)
    vim.wait(200)

    assert.are.same({ '.' }, client.server_capabilities.completionProvider.triggerCharacters)
  end)

  it('leaves a client alone when the source list does not name lsp', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)

    assert.are.same({ '.' }, client.server_capabilities.completionProvider.triggerCharacters)
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)

  -- enable_completions() reads triggerCharacters, and installs the autotrigger
  -- autocmds, only on a buffer handle's first enable() -- so a synchronous
  -- LspAttach handler in the user's own config, calling enable() before ZCmp's
  -- scheduled attach runs, used to leave both stuck at the server's own list.
  it('reclaims wiring from a client the user already enabled themselves', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)

    vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = false })

    local calls = {}
    helpers.stub(vim.lsp.completion, 'enable', function(enable, client_id, buf)
      calls[#calls + 1] = { enable, client_id, buf }
    end)

    lsp.sync(bufnr, { opts = { autotrigger = true, extend_trigger_characters = true } })

    assert.are.same({ false, client.id, bufnr }, calls[1])
    assert.are.same({ true, client.id, bufnr }, calls[2])
  end)

  -- The wholesale drop above unwires every client of the buffer, including
  -- ones already correctly wired; if that drop bypasses forget()'s
  -- bookkeeping, a client whose reattach then fails is left with
  -- `original[id]` still set and nothing left to ever restore it from.
  it('does not orphan a wired client whose reattach fails during the wholesale drop', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client1 = start(bufnr)
    assert.is_true(lsp.attach(client1, bufnr, {}))
    assert.contains(client1.server_capabilities.completionProvider.triggerCharacters, 'a')

    local id2 = assert(vim.lsp.start({ name = 'zcmp-test-2', cmd = server }, { bufnr = bufnr }))
    vim.wait(2000, function()
      return vim.lsp.get_client_by_id(id2) ~= nil
    end)
    -- client2 stays unwired on purpose -- that is what forces sync()'s
    -- reclaim branch, which drops every client of the buffer at once.

    helpers.stub(vim.lsp.completion, 'enable', function(enable, client_id)
      if enable and client_id == client1.id then
        error('simulated failure')
      end
    end)

    lsp.sync(bufnr, { opts = {} })

    -- Restored through unwire()'s forget(), not left as whatever the failed
    -- reattach's own widening happened to leave behind.
    assert.are.same({ '.' }, client1.server_capabilities.completionProvider.triggerCharacters)
  end)

  -- LspDetach fires M.forget() synchronously, on its own, well before the
  -- LspDetach handler's scheduled M.sync() pass runs.
  it('forget() restores triggerCharacters once the only buffer holding a client forgets it', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return autotriggers(bufnr) > 0
    end)
    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')

    lsp.forget(bufnr, client.id)

    assert.are.same({ '.' }, client.server_capabilities.completionProvider.triggerCharacters)
  end)

  it('forget() leaves the widened list alone while another buffer still holds the client', function()
    local first = helpers.buffer()
    local second = helpers.buffer()
    vim.api.nvim_set_current_buf(first)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    local client = start(first)
    helpers.settle(first)
    vim.wait(500, function()
      return autotriggers(first) > 0
    end)
    vim.lsp.buf_attach_client(second, client.id)
    vim.api.nvim_set_current_buf(second)
    helpers.settle(second)
    vim.wait(500, function()
      return autotriggers(second) > 0
    end)
    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')

    lsp.forget(first, client.id)

    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')
  end)

  -- :e! discards and rereads the buffer, which fires LspDetach; a config
  -- that reattaches a client on BufReadPost (as vim.lsp.enable()'s autostart
  -- does) reuses the still-running client id and does so synchronously,
  -- before any of zcmp's own scheduled passes land. Left the buffer with a
  -- client zcmp thought was already wired and no autotrigger to show for it.
  it('recovers the autotrigger from :e!, which detaches and reattaches the same client id', function()
    local dir = helpers.tempdir()
    local path = dir .. '/file.txt'
    helpers.write(path, 'one\n')
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return autotriggers(bufnr) > 0
    end)
    assert.are.equal(1, autotriggers(bufnr))

    local reattach = vim.api.nvim_create_autocmd('BufReadPost', {
      buffer = bufnr,
      callback = function(args)
        vim.lsp.start({ name = 'zcmp-test', cmd = server }, { bufnr = args.buf })
      end,
    })

    vim.cmd('edit!')
    vim.api.nvim_del_autocmd(reattach)

    vim.wait(500, function()
      return autotriggers(bufnr) > 0
    end)
    assert.are.equal(1, autotriggers(bufnr))
    assert.are.equal(1, #vim.lsp.get_clients({ bufnr = bufnr }))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

-- Three routes reach vim.lsp.completion's restart, any one enough on its
-- own: M.attach()'s own wiring (`wired[bufnr]`), M._omnifunc() itself
-- called straight off 'complete' with no `wired` lookup at all, and a plain
-- `o` flag whose 'omnifunc' Neovim's own LSP attach handler set to route
-- into the same M._omnifunc(). Neither a client attached with no omnifunc
-- route in 'complete', nor an omnifunc route with no client attached, is
-- any of them.
describe('asking the server again while a menu is open', function()
  -- The whole point of the opt: vim.lsp.completion consults the (widened)
  -- trigger list only after `if vim.fn.pumvisible() ~= 0 then return end`, so
  -- with a menu on screen the server is never asked again unless it answered
  -- `isIncomplete`. See lsp.lua's `retrigger()`.
  it('installs the TextChangedP hook on the buffer it wired', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp' } } })

    assert.is_false(lsp.retriggering(bufnr))
    start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return lsp.retriggering(bufnr)
    end)

    assert.is_true(lsp.retriggering(bufnr))
  end)

  it('leaves it off when the provider says retrigger = false', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({
      sources = {
        default = { 'lsp' },
        providers = { lsp = { opts = { retrigger = false } } },
      },
    })

    start(bufnr)
    helpers.settle(bufnr)
    vim.wait(200, function()
      return lsp.retriggering(bufnr)
    end)

    assert.is_false(lsp.retriggering(bufnr))
  end)

  -- One hook per buffer, dropped with the last client -- the same lifecycle
  -- `wired` has, so a buffer zcmp no longer drives is not left asking.
  it('drops it once the last client is forgotten', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return lsp.retriggering(bufnr)
    end)
    assert.is_true(lsp.retriggering(bufnr))

    lsp.forget(bufnr, client.id)

    assert.is_false(lsp.retriggering(bufnr))
  end)

  it('is one hook however many clients the buffer holds', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp' } } })

    local first = start(bufnr)
    -- A second *client*, not the same one again: vim.lsp.start() reuses a
    -- client whose config matches, so the name has to differ.
    local second_id = assert(vim.lsp.start({ name = 'zcmp-test-2', cmd = server }, { bufnr = bufnr }))
    local second = assert(vim.lsp.get_client_by_id(second_id))
    helpers.settle(bufnr)
    vim.wait(500, function()
      return lsp.retriggering(bufnr)
    end)

    lsp.forget(bufnr, first.id)
    assert.is_true(lsp.retriggering(bufnr), 'dropped while a client still holds the buffer')

    lsp.forget(bufnr, second.id)
    assert.is_false(lsp.retriggering(bufnr))
  end)
end)

describe('M.may_relocate()', function()
  it('answers false with nothing wired and nothing attached', function()
    local bufnr = helpers.buffer()
    assert.is_false(lsp.may_relocate(bufnr))
  end)

  it('answers true once M.attach() has wired a client (route 1)', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    local client = start(bufnr)

    assert.is_true(lsp.attach(client, bufnr, {}))

    assert.is_true(lsp.may_relocate(bufnr))
  end)

  -- The motivating false-positive case: a client attached for hover or
  -- diagnostics, with no `lsp` provider's entry in 'complete' at all -- the
  -- buffer's source list may omit the provider, or a third party may have
  -- called vim.lsp.completion.enable() itself.
  it('answers false for a client attached without the omnifunc entry in \'complete\'', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)
    vim.bo[bufnr].complete = '.,w,b'

    assert.is_false(lsp.may_relocate(bufnr))
  end)

  it('answers false for the omnifunc entry in \'complete\' with no client attached', function()
    local bufnr = helpers.buffer()
    vim.bo[bufnr].complete = lsp.source() .. ',.^100'

    assert.is_false(lsp.may_relocate(bufnr))
  end)

  -- Route 2: reachable with the `zcmp.lsp` module under any provider id --
  -- M.source() names the same entry regardless of which id put it in
  -- 'complete' -- and with no M.attach() call at all, so `wired` stays empty.
  it('answers true for the omnifunc entry in \'complete\' with a client attached, unwired (route 2)', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)
    vim.bo[bufnr].complete = lsp.source() .. ',.^100,w^100,b^100'

    assert.is_true(lsp.may_relocate(bufnr))
  end)

  -- Matched as a whole comma-separated element -- a `max_items` suffix is
  -- still the same entry, but another provider's entry that merely contains
  -- the same text is not.
  it('matches the entry with its own suffix, not merely as a substring', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)

    vim.bo[bufnr].complete = ("Fv:lua.require'other'.%s"):format(lsp.source())
    assert.is_false(lsp.may_relocate(bufnr))

    vim.bo[bufnr].complete = lsp.source() .. '^50'
    assert.is_true(lsp.may_relocate(bufnr))
  end)

  -- Route 3: a plain `o` flag reaches the same `trigger()` through
  -- 'omnifunc', but only when that option is Neovim's own LSP omnifunc --
  -- the value is what tells this apart from a user's or another plugin's
  -- own omnifunc left under `o`, which has no route to the restart.
  it('answers true for the o flag with core\'s LSP omnifunc (route 3)', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)
    vim.bo[bufnr].omnifunc = lsp.source():sub(2)
    vim.bo[bufnr].complete = 'o,.^100'

    assert.is_true(lsp.may_relocate(bufnr))
  end)

  -- Core writes 'omnifunc' as the function value itself from 0.13 on, and as
  -- the name on the 0.12 floor. Both reach the same `trigger()`; matching
  -- only the name made this route dead on 0.13.
  it('answers true for the o flag with core\'s LSP omnifunc as a function value (route 3)', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)
    -- 0.13+ writes the function value itself; the 0.12 floor rejects a
    -- function as an option value, and so can never reach this shape.
    if not pcall(function()
      vim.bo[bufnr].omnifunc = vim.lsp.omnifunc
    end) then
      return
    end
    vim.bo[bufnr].complete = 'o,.^100'

    assert.is_true(lsp.may_relocate(bufnr))
  end)

  it('answers false for the o flag with a foreign omnifunc', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    start(bufnr)
    vim.bo[bufnr].omnifunc = 'v:lua.SomeOtherPlugin.omnifunc'
    vim.bo[bufnr].complete = 'o,.^100'

    assert.is_false(lsp.may_relocate(bufnr))
  end)

  it('answers false for the o flag with core\'s LSP omnifunc but no client attached', function()
    local bufnr = helpers.buffer()
    vim.bo[bufnr].omnifunc = lsp.source():sub(2)
    vim.bo[bufnr].complete = 'o,.^100'

    assert.is_false(lsp.may_relocate(bufnr))
  end)

  -- `wired` indexes by real buffer number, not the API's `0`-means-current
  -- convention -- a caller passing `0` reads whatever buffer happens to be
  -- current instead, which is not `bufnr` here.
  it('reads wiring by real buffer number, not 0', function()
    local bufnr = helpers.buffer()
    local client = start(bufnr)
    assert.is_true(lsp.attach(client, bufnr, {}))

    local other = helpers.buffer()
    vim.api.nvim_set_current_buf(other)

    assert.is_false(lsp.may_relocate(0))
    assert.is_true(lsp.may_relocate(bufnr))
  end)
end)
