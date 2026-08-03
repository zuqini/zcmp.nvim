local config = require('zcmp.config')
local core = require('zcmp.sources.snippets')
local helpers = require('helpers')

-- The tests put the cursor after the last character, which is where it sits
-- in insert mode -- the only mode a completefunc and a CompleteDone handler
-- ever run in. Normal mode clamps that column back one, which computes an
-- expansion start one byte short of the trigger.
local virtualedit
before_each(function()
  helpers.reset()
  virtualedit = vim.o.virtualedit
  vim.o.virtualedit = 'onemore'
end)
after_each(function()
  vim.o.virtualedit = virtualedit
  helpers.cleanup()
end)

describe('snippet source machinery', function()
  it('offers the whole non-blank run for replacement', function()
    helpers.buffer({ 'say <di' })

    assert.are.equal(4, core.findstart())
  end)

  it('fuzzy-matches triggers and shows the trigger alone', function()
    local answer = core.complete('cl', {
      { trigger = 'console.log', description = 'Log' },
      { trigger = 'for', description = 'Loop' },
    })

    assert.are.equal(1, #answer.words)
    local item = answer.words[1]
    assert.are.equal('console.log', item.word)
    assert.are.equal('console.log', item.abbr)
    assert.are.equal('Snippet', item.kind)
    assert.are.equal('Log', item.menu)
    assert.are.equal('always', answer.refresh)
  end)

  it('keeps the part of the run that is not the trigger', function()
    local answer = core.complete('(req', { { trigger = 'req', body = 'x' } })

    assert.are.equal('(req', answer.words[1].word)
    assert.are.equal('req', answer.words[1].abbr)
    assert.are.equal(1, answer.words[1].user_data.zcmp_snip.keep)
  end)

  it('caps at the limit and strips documentation when told to', function()
    local candidates = {}
    for i = 1, 5 do
      candidates[i] = { trigger = 'trig' .. i, description = 'd', body = 'b' }
    end

    local answer = core.complete('', candidates, { limit = 2, documentation = false })

    assert.are.equal(2, #answer.words)
    assert.are.equal('', answer.words[1].menu)
    assert.are.equal('', answer.words[1].info)
  end)

  it('resolves a deferred docstring only for what matched', function()
    local asked = 0
    local answer = core.complete('fn', {
      {
        trigger = 'fn',
        info = function()
          asked = asked + 1
          return 'fn(${1})'
        end,
      },
      {
        trigger = 'unrelated_zz',
        info = function()
          asked = asked + 1
          return 'nope'
        end,
      },
    })

    assert.are.equal('fn(${1})', answer.words[1].info)
    assert.are.equal(1, asked)
  end)

  it('replaces the accepted trigger with its expanded body', function()
    local expanded
    config.setup({
      snippets = {
        expand = function(body)
          expanded = body
        end,
      },
    })
    helpers.buffer({ 'local (req' })

    local answer = core.complete('(req', { { trigger = 'req', body = 'require("${1}")' } })
    core.expand(answer.words[1])

    assert.are.equal('local (', vim.api.nvim_get_current_line())
    assert.are.equal('require("${1}")', expanded)
  end)

  it('expands by reference when the candidate carries no body', function()
    local ran = false
    helpers.buffer({ 'fn' })

    local answer = core.complete('fn', {
      {
        trigger = 'fn',
        expand = function()
          ran = true
        end,
      },
    })
    core.expand(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.is_true(ran)
  end)

  it('expands nothing it did not offer', function()
    helpers.buffer({ 'word' })

    core.complete('', {})
    core.expand({ word = 'word', user_data = { zcmp_snip = { id = 999999 } } })

    assert.are.equal('word', vim.api.nvim_get_current_line())
  end)
end)

describe('the luasnip adapter', function()
  local adapter = require('zcmp.sources.snippets.luasnip')

  ---@param snips table[]
  ---@param expanded table
  local function stub_luasnip(snips, expanded)
    helpers.stub(package.loaded, 'luasnip', {
      get_snippet_filetypes = function()
        return { 'lua', 'all' }
      end,
      get_snippets = function(filetype)
        return filetype == 'lua' and snips or {}
      end,
      get_id_snippet = function(id)
        for _, snip in ipairs(snips) do
          if snip.id == id then
            return snip
          end
        end
      end,
      snip_expand = function(snip)
        expanded[#expanded + 1] = snip
      end,
    })
  end

  it('will not start without luasnip', function()
    local ok, err = pcall(adapter.enable)

    assert.is_false(ok)
    assert.is_true(tostring(err):find('luasnip', 1, true) ~= nil)
  end)

  it('offers triggers, skipping hidden, regex and condition-refused ones', function()
    helpers.buffer({ 'fn' })
    stub_luasnip({
      {
        trigger = 'fn',
        name = 'Function',
        dscr = { 'A function' },
        id = 1,
        get_docstring = function()
          return { 'function ${1}()', 'end' }
        end,
      },
      { trigger = 'shy', hidden = true, id = 2 },
      { trigger = 'rx%d+', regTrig = true, id = 3 },
      {
        trigger = 'fntx',
        id = 4,
        show_condition = function()
          return false
        end,
      },
    }, {})
    adapter.enable()

    local answer = adapter.completefunc(0, 'fn')

    assert.are.equal(1, #answer.words)
    assert.are.equal('fn', answer.words[1].word)
    assert.are.equal('A function', answer.words[1].menu)
    assert.are.equal('function ${1}()\nend', answer.words[1].info)
  end)

  it('expands the accepted snippet through luasnip, by reference', function()
    helpers.buffer({ 'fn' })
    local expanded = {}
    local snips = { { trigger = 'fn', id = 1 } }
    stub_luasnip(snips, expanded)
    adapter.enable()

    local answer = adapter.completefunc(0, 'fn')
    core.expand(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(snips[1], expanded[1])
  end)
end)

describe('the nvim-snippets adapter', function()
  local adapter = require('zcmp.sources.snippets.nvim_snippets')

  it('will not start without nvim-snippets', function()
    local ok, err = pcall(adapter.enable)

    assert.is_false(ok)
    assert.is_true(tostring(err):find('nvim-snippets', 1, true) ~= nil)
  end)

  it('offers every prefix of a snippet, with the body joined', function()
    helpers.buffer({ '' })
    helpers.stub(package.loaded, 'snippets', {
      load_snippets_for_ft = function()
        return {
          req = {
            prefix = 'req',
            body = { 'local ${1} = require("${2}")', '${0}' },
            description = 'Require a module',
          },
          multi = { prefix = { 'multi', 'm2' }, body = 'multi body' },
        }
      end,
    })
    adapter.enable()

    local answer = adapter.completefunc(0, '')
    local triggers = {}
    for _, item in ipairs(answer.words) do
      triggers[#triggers + 1] = item.word
    end
    table.sort(triggers)

    assert.are.same({ 'm2', 'multi', 'req' }, triggers)
  end)

  it('expands the accepted body through snippets.expand', function()
    local expanded
    config.setup({
      snippets = {
        expand = function(body)
          expanded = body
        end,
      },
    })
    helpers.buffer({ 'req' })
    helpers.stub(package.loaded, 'snippets', {
      load_snippets_for_ft = function()
        return { req = { prefix = 'req', body = 'require("${1}")' } }
      end,
    })
    adapter.enable()

    local answer = adapter.completefunc(0, 'req')
    core.expand(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal('require("${1}")', expanded)
  end)
end)
