local child = require('child')
local helpers = require('helpers')

local ROOT = vim.fn.getcwd()

---@param fragment string
---@return table
local function run(fragment)
  local results, log = child.run(fragment, ROOT, helpers.tempdir())
  assert.is_true(next(results) ~= nil, 'child produced nothing:\n' .. log)
  return results
end

---A directory to complete paths out of, and a file in it to be editing.
---@return string
local function tree()
  local dir = helpers.tempdir()
  helpers.write(dir .. '/alpha.txt')
  helpers.write(dir .. '/beta.txt')
  return dir
end

after_each(helpers.cleanup)

describe('a real menu', function()
  it('opens by itself and offers what the sources answer', function()
    local results = run(([[
      require('zcmp').setup({ sources = { default = { 'path', 'buffer' } } })
      vim.cmd('edit %s/main.txt')
      scenario({
        -- Nothing here presses <C-n>: 'autocomplete' is what opens the menu.
        { name = 'path', keys = 'i./al', then_keys = '<C-y>' },
        {
          name = 'word',
          lines = { 'alphabetical', '' },
          cursor = { 2, 0 },
          keys = 'ialph',
          then_keys = '<C-n><C-y>',
        },
        { name = 'nothing', keys = 'izzq' },
      }, done)
    ]]):format(tree()))

    -- The path source marks its first item, so <C-y> alone accepts it.
    assert.contains(results.path.offered, './alpha.txt')
    assert.are.same({ './alpha.txt' }, results.path.lines)

    assert.contains(results.word.offered, 'alphabetical')
    assert.are.same({ 'alphabetical', 'alphabetical' }, results.word.lines)

    assert.are.same({}, results.nothing.offered)
    assert.are.same({ 'zzq' }, results.nothing.lines)
  end)

  -- What 'complete' gives that vim.fn.complete() cannot: each source decides
  -- for itself where the text it replaces begins.
  it('takes each source from its own start column', function()
    local results = run(([[
      require('zcmp').setup({ sources = { default = { 'path', 'buffer' } } })
      vim.cmd('edit %s/main.txt')
      scenario({
        { name = 'anchored', keys = 'ilocal f = ./al', then_keys = '<C-y>' },
      }, done)
    ]]):format(tree()))

    assert.are.same({ 'local f = ./alpha.txt' }, results.anchored.lines)
  end)
end)

describe('the keys', function()
  it('indents with <Tab>, and accepts what is selected with <CR>', function()
    local results = run(([[
      require('zcmp').setup({
        keymap = { preset = 'enter' },
        sources = { default = { 'path', 'buffer' } },
      })
      vim.cmd('edit %s/main.txt')
      vim.o.expandtab = false
      scenario({
        { name = 'indent', keys = 'i<Tab>x', delay = 300 },
        { name = 'accept', keys = 'i./al', then_keys = '<CR>' },
        { name = 'newline', keys = 'izzq', then_keys = '<CR>x' },
      }, done)
    ]]):format(tree()))

    assert.are.same({ '\tx' }, results.indent.lines)
    -- Nothing was selected by hand: 'preselect' is what puts an item under <CR>.
    assert.are.same({ './alpha.txt' }, results.accept.lines)
    -- With no menu up, <CR> is a newline again.
    assert.are.same({ 'zzq', 'x' }, results.newline.lines)
  end)

  -- Core's own scanners mark no preselect, so a buffer word is only under <CR>
  -- if the key asks for the first item rather than the selected one.
  it('takes the first match when <CR> is bound to select_and_accept', function()
    local results = run([[
      require('zcmp').setup({
        keymap = { preset = 'enter', ['<CR>'] = { 'select_and_accept', 'fallback' } },
        sources = { default = { 'buffer' } },
      })
      scenario({
        {
          name = 'first',
          lines = { 'alphabetical', '' },
          cursor = { 2, 0 },
          keys = 'ialph',
          then_keys = '<CR>',
        },
      }, done)
    ]])

    assert.are.same({ 'alphabetical', 'alphabetical' }, results.first.lines)
  end)

  it('hands a key back to the mapping it displaced', function()
    local results = run(([[
      -- An autopair plugin's <CR> is global and installed before zcmp attaches.
      vim.keymap.set('i', '<CR>', function() return 'PAIRED' end, { expr = true })
      require('zcmp').setup({
        keymap = { preset = 'enter' },
        sources = { default = { 'path', 'buffer' } },
      })
      vim.cmd('edit %s/main.txt')
      scenario({
        { name = 'fallback', keys = 'izzq', then_keys = '<CR>' },
        { name = 'accepted', keys = 'i./al', then_keys = '<CR>' },
      }, done)
    ]]):format(tree()))

    -- No menu, so <CR> reaches the mapping that was already there.
    assert.are.same({ 'zzqPAIRED' }, results.fallback.lines)
    -- A selected item, so zcmp keeps the key and the other mapping never runs.
    assert.are.same({ './alpha.txt' }, results.accepted.lines)
  end)

  it('opens the menu on request when it does not open by itself', function()
    local results = run([[
      require('zcmp').setup({
        completion = { menu = { auto_show = false } },
        keymap = { preset = 'default', ['<C-l>'] = { 'show' } },
        sources = { default = { 'buffer' } },
      })
      scenario({
        { name = 'quiet', lines = { 'alphabetical', '' }, cursor = { 2, 0 }, keys = 'ialph' },
        {
          name = 'asked',
          lines = { 'alphabetical', '' },
          cursor = { 2, 0 },
          keys = 'ialph<C-l>',
          then_keys = '<C-y>',
        },
      }, done)
    ]])

    assert.are.same({}, results.quiet.offered)
    assert.contains(results.asked.offered, 'alphabetical')
    assert.are.same({ 'alphabetical', 'alphabetical' }, results.asked.lines)
  end)
end)
