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

    assert.are.same({
      'Environment',
      'Setup',
      'Sources',
      'This buffer',
      'Other completion engines',
      'Reporting a bug',
    }, report.sections)
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
    vim.api.nvim_set_current_buf(scratch)

    local report = recorder()
    require('zcmp.health').check()

    assert.are.equal('warn', entry(report, 'not attached here').kind)
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
