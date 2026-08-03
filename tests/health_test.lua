local helpers = require('helpers')

---A recording stand-in for vim.health: every call, in order, with the section
---it was made under.
---@return { sections: string[], entries: { kind: string, message: string, section: string }[] }
local function recorder()
  local report = { sections = {}, entries = {} }
  local function record(kind)
    return function(message)
      report.entries[#report.entries + 1] = {
        kind = kind,
        message = tostring(message),
        section = report.sections[#report.sections],
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

    assert.are.equal('warn', entry(report, 'not enabled').kind)
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

    assert.are.equal('warn', entry(report, "'completeopt' is").kind)
  end)
end)
