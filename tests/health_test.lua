local helpers = require('helpers')

---A recording stand-in for vim.health: every call, in order, with the section
---it was made under.
---@return { sections: string[], entries: { kind: string, message: string, section: string, advice: string[]? }[] }
local function recorder()
  local report = { sections = {}, entries = {} }
  local function record(kind)
    return function(message, advice)
      report.entries[#report.entries + 1] = {
        kind = kind,
        message = tostring(message),
        section = report.sections[#report.sections],
        advice = advice,
      }
    end
  end

  helpers.stub(vim, 'health', {
    start = function(name)
      report.sections[#report.sections + 1] = name
    end,
    ok = record('ok'),
    warn = record('warn'),
    error = record('error'),
    info = record('info'),
  })
  return report
end

---@param report table
---@param pattern string
---@return table?
local function entry(report, pattern)
  for _, item in ipairs(report.entries) do
    if item.message:find(pattern, 1, true) then
      return item
    end
  end
  return nil
end

---An in-process language server that answers completion, so a
---completion-capable client can be attached without a binary to talk to.
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
local function start(bufnr)
  local id = assert(vim.lsp.start({ name = 'zcmp-health-test', cmd = server }, { bufnr = bufnr }))
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
  end)
  return id
end

local function stop_clients()
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop()
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients() == 0
  end)
end

before_each(helpers.reset)
after_each(helpers.cleanup)

describe(':checkhealth zcmp', function()
  it('reports every section', function()
    local report = recorder()
    require('zcmp.health').check()

    local sections = report.sections
    assert.are.equal(6, #sections)
    assert.are.same({ 'Environment', 'Setup', 'Sources' }, { sections[1], sections[2], sections[3] })
    -- The fourth names the buffer it reported on.
    assert.is_not_nil(sections[4]:match('^Buffer %d+'))
    assert.are.same({ 'Other completion engines', 'Reporting a bug' }, { sections[5], sections[6] })
  end)

  -- Every section after the first reads an option that arrived with the floor,
  -- and an unknown option raises rather than answering nil -- which aborted the
  -- run and took the one line explaining why down with it.
  it('stops after the environment below the floor', function()
    local has = vim.fn.has
    helpers.stub(vim.fn, 'has', function(feature)
      return feature == 'nvim-0.12' and 0 or has(feature)
    end)

    local report = recorder()
    require('zcmp.health').check()

    assert.are.same({ 'Environment' }, report.sections)
    assert.are.equal('error', entry(report, '0.12.0+ is required').kind)
  end)

  -- A provider may declare both `flags` and a `module`; the flags still serve
  -- when the module is missing, and a plain tick hides the one thing
  -- checkhealth is here to find.
  it('names the problem of a source that is serving anyway', function()
    require('zcmp').setup({
      sources = {
        default = { 'half' },
        providers = { half = { name = 'Half', flags = { '.' }, max_items = 100, module = 'no_such_module' } },
      },
    })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    local report = recorder()
    require('zcmp.health').check(bufnr)

    local found = entry(report, 'not on the runtimepath')
    assert.are.equal('warn', found.kind)
    assert.is_true(found.message:find('.^100', 1, true) ~= nil)
  end)

  -- list() is the report path, and it used to run the provider module's
  -- enable(): running :checkhealth reconfigured the plugin it was reporting on.
  it('starts no provider module of its own', function()
    local started = 0
    helpers.stub(package.loaded, 'fake_source', {
      completefunc = function() end,
      enable = function()
        started = started + 1
      end,
    })
    require('zcmp.config').setup({
      sources = { default = { 'fake' }, providers = { fake = { module = 'fake_source' } } },
    })

    recorder()
    require('zcmp.health').check(helpers.buffer())

    assert.are.equal(0, started)
  end)

  it('carries the version, so a bug report says which zcmp it is about', function()
    local report = recorder()
    require('zcmp.health').check()

    assert.is_not_nil(entry(report, 'zcmp ' .. require('zcmp').version))
  end)

  it('says so when nothing has taken over completion', function()
    local report = recorder()
    require('zcmp.health').check()

    local warned = entry(report, 'not enabled')
    assert.are.equal('warn', warned.kind)
    -- ':ZCmp' does not exist before setup() has ever run, so the remedy is
    -- setup() itself, not the command the Buffer section's hint points at
    -- once it exists.
    assert.matches("require%('zcmp'%)%.setup%(%)", warned.advice[1])
  end)

  -- After setup() the command exists; the remedy for "not enabled" is now the
  -- same one the Buffer section's hint gives for the identical state.
  it("gives the ':ZCmp enable' remedy once setup() has run and been undone", function()
    require('zcmp').setup({})
    require('zcmp').disable()

    local report = recorder()
    require('zcmp.health').check()

    local warned = entry(report, 'not enabled')
    assert.are.equal('warn', warned.kind)
    assert.matches(':ZCmp enable', warned.advice[1])
  end)

  it('reports an attached buffer and what is serving it', function()
    require('zcmp').setup({ sources = { default = { 'buffer' } } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal('ok', entry(report, 'enabled').kind)
    assert.are.equal('ok', entry(report, '.^100,w^100,b^100').kind)
  end)

  -- 'completeopt' is global-local: check_setup() reads vim.o, which says
  -- nothing about a local value sitting only in this buffer.
  it("warns about a 'completeopt' set locally in the buffer, even though the global value matches", function()
    require('zcmp').setup({})
    local editing = helpers.buffer()
    helpers.settle(editing)
    vim.bo[editing].completeopt = 'menu'
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal(('Buffer %d'):format(editing), report.sections[4])
    local found = entry(report, "'completeopt' is set locally")
    assert.are.equal('warn', found.kind)
    -- zcmp never writes the local slot, so blaming "after zcmp did" here
    -- would describe nothing; the remedy is the actionable line instead.
    assert.is_nil(table.concat(found.advice, '\n'):find('after zcmp did', 1, true))
    assert.is_true(table.concat(found.advice, '\n'):find(':setlocal completeopt<', 1, true) ~= nil)
  end)

  -- "My snippets do not show up" is usually this: the provider is listed and
  -- the module it needs is not installed.
  it('names a provider whose module is missing', function()
    require('zcmp').setup({ sources = { default = { 'snippets' } } })
    helpers.settle(helpers.buffer())

    local report = recorder()
    require('zcmp.health').check()

    local missing = entry(report, 'zsnip.complete')
    assert.are.equal('warn', missing.kind)
    assert.are.equal('Sources', missing.section)
  end)

  it('errors when sources.default is empty', function()
    require('zcmp').setup({ sources = { default = {} } })
    local bufnr = helpers.buffer()
    helpers.settle(bufnr)

    local report = recorder()
    require('zcmp.health').check(bufnr)

    local found = entry(report, 'no sources')
    assert.are.equal('error', found.kind)
    assert.matches('sources%.default', found.message)
  end)

  -- An explicit, non-inheriting per_filetype list is what the user asked for,
  -- so an empty one is news, not a fault -- and it is not sources.default's.
  it('names sources.per_filetype.<ft> and only informs when that is the empty one', function()
    require('zcmp').setup({
      sources = { default = { 'buffer' }, per_filetype = { markdown = {} } },
    })
    local bufnr = helpers.buffer()
    vim.bo[bufnr].filetype = 'markdown'
    helpers.settle(bufnr)

    local report = recorder()
    require('zcmp.health').check(bufnr)

    local found = entry(report, 'no sources')
    assert.are.equal('info', found.kind)
    assert.matches('sources%.per_filetype%.markdown', found.message)
  end)

  it('is quiet about a source with nothing to offer this buffer', function()
    require('zcmp').setup({ sources = { default = { 'lsp' } } })
    helpers.settle(helpers.buffer())

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal('info', entry(report, 'nothing to serve').kind)
  end)

  it('warns when a buffer is not one zcmp drives', function()
    require('zcmp').setup({})
    local scratch = vim.api.nvim_create_buf(false, true)

    local report = recorder()
    require('zcmp.health').check(scratch)

    assert.are.equal('warn', entry(report, 'not attached here').kind)
  end)

  -- :checkhealth runs inside its own nofile buffer, which zcmp never drives.
  it('reports on the buffer it was called from, not the checkhealth one', function()
    require('zcmp').setup({ sources = { default = { 'buffer' } } })
    local editing = helpers.buffer()
    helpers.settle(editing)
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal(('Buffer %d'):format(editing), report.sections[4])
    assert.are.equal('ok', entry(report, "'complete' = ").kind)
  end)

  -- A user whose `enabled` admits other buftypes still gets the alternate
  -- buffer reported on, not the checkhealth scratch buffer: which buffer zcmp
  -- drives is `buffer.attached()`'s question to answer, not buftype's.
  it('reports on the alternate buffer even when its buftype is not empty', function()
    require('zcmp').setup({ enabled = function() return true end, sources = { default = { 'buffer' } } })
    local editing = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(editing)
    helpers.settle(editing)
    helpers.buffer()

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal(('Buffer %d'):format(editing), report.sections[4])
  end)

  -- A buffer zcmp is not attached to -- disabled, or excluded by `enabled` --
  -- is still the one to report on: `check_buffer()` already explains why it
  -- is not attached, which is the case this check exists for.
  it('reports on the alternate buffer when zcmp is not attached to it', function()
    require('zcmp').setup({ enabled = function() return false end, sources = { default = { 'buffer' } } })
    local editing = helpers.buffer()
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal(('Buffer %d'):format(editing), report.sections[4])
    local warned = entry(report, 'not attached here')
    assert.are.equal('warn', warned.kind)
    -- `check_buffer()` cannot tell `enabled` apart from every other reason
    -- `wire()` detaches (`keymap.apply` raising, `'complete'` refused), so
    -- the hint names both rather than overclaiming the one it can show.
    assert.matches('enabled.*answered false', warned.advice[1])
    assert.matches('earlier pass reported an error', warned.advice[1])
  end)

  -- `enabled` excluding this buftype is not the reason once zcmp itself is
  -- off -- pointing at `enabled` here would send a user auditing the wrong
  -- option.
  it('explains that zcmp is disabled rather than blaming buftype', function()
    require('zcmp').setup({ sources = { default = { 'buffer' } } })
    require('zcmp').disable()
    local editing = helpers.buffer()

    local report = recorder()
    require('zcmp.health').check(editing)

    local warned = entry(report, 'not attached here')
    assert.are.equal('warn', warned.kind)
    assert.matches('zcmp is disabled', warned.advice[1])
    assert.matches(':ZCmp enable', warned.advice[1])
  end)

  -- Before setup() has ever run, ':ZCmp' does not exist -- the hint here must
  -- agree with the Setup section's, not point at a command there is none of.
  it('points at setup() rather than :ZCmp enable when setup() never ran', function()
    local editing = helpers.buffer()

    local report = recorder()
    require('zcmp.health').check(editing)

    local warned = entry(report, 'not attached here')
    assert.are.equal('warn', warned.kind)
    assert.matches('zcmp is disabled', warned.advice[1])
    assert.matches("require%('zcmp'%)%.setup%(%)", warned.advice[1])
  end)

  -- Two engines writing 'complete' and mapping <Tab> is the failure that looks
  -- like every other failure.
  it('warns about another completion engine in the same session', function()
    helpers.stub(package.loaded, 'blink.cmp', {})

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal('warn', entry(report, 'blink.cmp').kind)
  end)

  it('reports no rival engine when there is none', function()
    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal('ok', entry(report, 'none loaded').kind)
  end)

  it("notices 'completeopt' being taken over after setup", function()
    require('zcmp').setup({})
    vim.go.completeopt = 'menu'

    local report = recorder()
    require('zcmp.health').check()

    local found = entry(report, "'completeopt' is")
    assert.are.equal('warn', found.kind)
    assert.is_true(table.concat(found.advice, '\n'):find('after zcmp did', 1, true) ~= nil)
  end)

  -- The 'not enabled' warning above already covers this; comparing
  -- 'completeopt' against a config zcmp never applied would blame it for a
  -- value it had no part in.
  it("stays quiet about 'completeopt' while not enabled", function()
    vim.go.completeopt = 'menu'

    local report = recorder()
    require('zcmp.health').check()

    assert.is_nil(entry(report, "'completeopt' is"))
  end)

  describe('the LSP retrigger hook', function()
    after_each(stop_clients)

    it('reports it on once a completion-capable client is attached', function()
      require('zcmp').setup({ sources = { default = { 'lsp' } } })
      local bufnr = helpers.buffer()
      helpers.settle(bufnr)
      start(bufnr)
      vim.wait(500, function()
        return require('zcmp.lsp').retriggering(bufnr)
      end)

      local report = recorder()
      require('zcmp.health').check(bufnr)

      assert.are.equal('ok', entry(report, 'asking the LSP source again').kind)
    end)

    it('warns with retrigger = false among the reasons', function()
      require('zcmp').setup({
        sources = { default = { 'lsp' }, providers = { lsp = { opts = { retrigger = false } } } },
      })
      local bufnr = helpers.buffer()
      helpers.settle(bufnr)
      start(bufnr)
      vim.wait(200, function()
        return require('zcmp.lsp').retriggering(bufnr)
      end)

      local report = recorder()
      require('zcmp.health').check(bufnr)

      local found = entry(report, 'not asking the LSP source again')
      assert.are.equal('warn', found.kind)
      assert.is_true(table.concat(found.advice, '\n'):find('sources.providers.lsp.opts.retrigger', 1, true) ~= nil)
    end)

    it('warns when nothing installed the hook for an unrelated reason', function()
      require('zcmp').setup({ sources = { default = { 'buffer' } } })
      local bufnr = helpers.buffer()
      helpers.settle(bufnr)
      start(bufnr)
      vim.wait(200, function()
        return require('zcmp.lsp').available(bufnr)
      end)

      local report = recorder()
      require('zcmp.health').check(bufnr)

      assert.are.equal('warn', entry(report, 'not asking the LSP source again').kind)
    end)
  end)
end)
