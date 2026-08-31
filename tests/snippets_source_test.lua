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

  -- Every item says where its `word` replaces from, so ZCmp's CompleteDone
  -- handler can put the run back after vim.lsp.completion re-inserts the
  -- item at the keyword boundary instead.
  it('records where the run starts on each item', function()
    helpers.buffer({ 'say <di' })

    local answer = core.complete('test', { { trigger = '<div', body = 'x' } })

    assert.are.equal(4, answer.words[1].user_data.zcmp_start)
  end)

  it('fuzzy-matches triggers and shows the trigger alone', function()
    helpers.buffer({ 'cl' })

    local answer = core.complete('test', {
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

  -- The luasnip adapter forwards snip.trigger with no type check; a nil or
  -- non-string trigger used to raise `table index is nil` on the
  -- by_trigger[candidate.trigger] assignment rather than being skipped.
  it('skips a candidate with a nil, empty or non-string trigger instead of raising', function()
    helpers.buffer({ 'cl' })

    local answer = core.complete('test', {
      { trigger = 'console.log', description = 'Log' },
      { description = 'no trigger' },
      { trigger = '', description = 'empty trigger' },
      { trigger = false, description = 'boolean trigger' },
    })

    assert.are.equal(1, #answer.words)
    assert.are.equal('console.log', answer.words[1].abbr)
  end)

  -- LuaSnip does not constrain a snippet's `name`, which `description()`
  -- falls through to -- a table there used to reach core.complete()'s menu
  -- field untyped and raise E730 on every keystroke that reached the source,
  -- with the item still landing.
  it('tolerates a table-valued description instead of raising', function()
    helpers.buffer({ 'cl' })

    local answer = core.complete('test', {
      { trigger = 'console.log', description = { 'Log', 'it' } },
    })

    assert.are.equal(1, #answer.words)
    assert.are.equal('console.log', answer.words[1].abbr)
    assert.are.equal('', answer.words[1].menu)
  end)

  -- Same contract for `body`'s fallback into `info` -- only reached when the
  -- candidate has no `info` of its own.
  it('tolerates a table-valued body instead of raising', function()
    helpers.buffer({ 'cl' })

    local answer = core.complete('test', {
      { trigger = 'console.log', body = { 'console.log(${1})' } },
    })

    assert.are.equal(1, #answer.words)
    assert.are.equal('console.log', answer.words[1].abbr)
    assert.are.equal('', answer.words[1].info)
  end)

  it('keeps the part of the run that is not the trigger', function()
    helpers.buffer({ '(req' })

    local answer = core.complete('test', { { trigger = 'req', body = 'x' } })

    assert.are.equal('(req', answer.words[1].word)
    assert.are.equal('req', answer.words[1].abbr)
    assert.are.equal(1, answer.words[1].user_data.zcmp_snip.keep)
  end)

  describe('splitting the run where a trigger contains the boundary', function()
    local candidates = {
      { trigger = '<div', body = 'x' },
      { trigger = 'console.log', body = 'x' },
      { trigger = '$x', body = 'x' },
      { trigger = 'x.y*', body = 'x' },
      { trigger = 'req', body = 'x' },
      { trigger = 'café', body = 'x' },
      { trigger = 'number', body = 'x' },
      { trigger = 'fn(', body = 'x' },
      { trigger = '.then', body = 'x' },
      { trigger = '@!attribute', body = 'x' },
      { trigger = '.ABC', body = 'x' },
    }

    local cases = {
      { run = 'x<di', word = 'x<div', keep = 1 },
      { run = 'x<dv', word = 'x<div', keep = 1 },
      { run = 'x.tn', word = 'x.then', keep = 1 },
      { run = '#@attr', word = '#@!attribute', keep = 1 },
      { run = 'x.a', word = 'x.ABC', keep = 1 },
      { run = 'a=console.lo', word = 'a=console.log', keep = 2 },
      { run = 'foo$x', word = 'foo$x', keep = 3 },
      { run = '(x.y', word = '(x.y*', keep = 1 },
      { run = '(req', word = '(req', keep = 1 },
      { run = '(café', word = '(café', keep = 1 },
    }
    for _, case in ipairs(cases) do
      it('keeps only what is not the trigger in ' .. case.run, function()
        helpers.buffer({ case.run })

        local answer = core.complete('test', candidates)

        assert.are.equal(1, #answer.words)
        assert.are.equal(case.word, answer.words[1].word)
        assert.are.equal(case.keep, answer.words[1].user_data.zcmp_snip.keep)
      end)
    end

    -- `zcafé` and `über` split only inside a character; the punctuation-only
    -- tails of `vim.`, `foo(` and `<<<` are nothing's head.
    for _, run in ipairs({ 'a=b+zzz', 'zcafé', 'über', 'vim.', 'foo(', '<<<' }) do
      it('offers nothing when no tail matches at any boundary in ' .. run, function()
        helpers.buffer({ run })

        local answer = core.complete('test', candidates)

        assert.are.same({}, answer.words)
      end)
    end

    it('costs no more than the longest trigger per keystroke', function()
      local many = {}
      for i = 1, 300 do
        many[i] = { trigger = 't' .. i .. '.x', body = 'x' }
      end
      helpers.buffer({ ('a.b(c);'):rep(143) })

      -- Only the last `longest` bytes of the run are split; every boundary in
      -- the rest of it used to open a fuzzy match, at hundreds of ms a keystroke.
      local started = vim.uv.hrtime()
      local answer = core.complete('test', many)
      local elapsed_ms = (vim.uv.hrtime() - started) / 1e6

      assert.are.same({}, answer.words)
      assert.is_true(elapsed_ms < 50, ('took %.1f ms'):format(elapsed_ms))
    end)
  end)

  -- 'autocomplete' asks after every space typed, and an empty run matches
  -- every trigger. A manual CTRL-N still lists them all, as Vim's own
  -- sources do.
  it("offers nothing on an empty run while 'autocomplete' is on", function()
    helpers.buffer({ 'say ' })
    local candidates = { { trigger = 'for', body = 'x' }, { trigger = '<div', body = 'x' } }

    helpers.stub(vim.o, 'autocomplete', true)
    local answer = core.complete('test', candidates)
    assert.are.same({}, answer.words)
    assert.are.equal('always', answer.refresh)

    vim.o.autocomplete = false
    assert.are.equal(2, #core.complete('test', candidates).words)
  end)

  it('caps at the limit and strips documentation when told to', function()
    helpers.buffer({ '' })
    local candidates = {}
    for i = 1, 5 do
      candidates[i] = { trigger = 'trig' .. i, description = 'd', body = 'b' }
    end

    local answer = core.complete('test', candidates, { limit = 2, documentation = false })

    assert.are.equal(2, #answer.words)
    assert.are.equal('', answer.words[1].menu)
    assert.are.equal('', answer.words[1].info)
  end)

  -- A bad opts.limit used to reach vim.fn.matchfuzzy({ limit = limit }) and
  -- raise E475 on every query.
  for _, case in ipairs({ '2', 0 }) do
    it(('falls back to the default limit and warns for %s'):format(vim.inspect(case)), function()
      helpers.buffer({ 'trig' })
      local candidates = {}
      for i = 1, 5 do
        candidates[i] = { trigger = 'trig' .. i }
      end

      local answer
      local notified = helpers.notifications(function()
        answer = core.complete('test', candidates, { limit = case })
      end)

      assert.are.equal(5, #answer.words)
      assert.is_true(helpers.notified(notified, 'opts.limit'))
    end)
  end

  -- sources.limit()'s report names the offender. A derived short label is
  -- unambiguous only for the two adapters shipped here; a third-party
  -- adapter's dotted module name is the only label that is unambiguous for
  -- everyone, so `owner` reaches the report verbatim.
  it('names the full dotted owner in a bad opts.limit report', function()
    helpers.buffer({ 'trig' })

    local notified = helpers.notifications(function()
      core.complete('zcmp.sources.snippets.nvim_snippets', { { trigger = 'trig' } }, { limit = 0 })
    end)

    assert.is_true(helpers.notified(notified, 'zcmp.sources.snippets.nvim_snippets opts.limit'))
  end)

  it('resolves a deferred docstring only for what matched', function()
    helpers.buffer({ 'fn' })
    local asked = 0
    local answer = core.complete('test', {
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

    local answer = core.complete('test', { { trigger = 'req', body = 'require("${1}")' } })
    core.accept(answer.words[1])

    assert.are.equal('local (', vim.api.nvim_get_current_line())
    assert.are.equal('require("${1}")', expanded)
  end)

  -- What vim.lsp.completion's restart leaves when the keyword boundary is
  -- inside the run: `x<div` re-inserted after `x<`. ZCmp's own CompleteDone
  -- handler trims that head, but it is in another augroup, and accept() must
  -- come out right whether it has run yet or not.
  it('replaces the trigger of a word re-inserted after its own head', function()
    local expanded
    config.setup({
      snippets = {
        expand = function(body)
          expanded = body
        end,
      },
    })
    helpers.stub(vim.o, 'virtualedit', 'onemore')
    helpers.buffer({ 'x<di' })
    local answer = core.complete('test', { { trigger = '<div', body = 'DIV' } })
    local item = answer.words[1]
    assert.are.equal('x<div', item.word)
    vim.api.nvim_set_current_line('x<' .. item.word)
    vim.api.nvim_win_set_cursor(0, { 1, 7 })

    core.accept(item)

    assert.are.equal('x', vim.api.nvim_get_current_line())
    assert.are.equal('DIV', expanded)
  end)

  it('expands by reference when the candidate carries no body', function()
    local ran = false
    helpers.buffer({ 'fn' })

    local answer = core.complete('test', {
      {
        trigger = 'fn',
        expand = function()
          ran = true
        end,
      },
    })
    core.accept(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.is_true(ran)
  end)

  it('reports a raising by-reference expand instead of propagating, and leaves the trigger deleted', function()
    helpers.buffer({ 'fn' })

    local answer = core.complete('test', {
      {
        trigger = 'fn',
        expand = function()
          error('boom')
        end,
      },
    })

    local notifications = helpers.notifications(function()
      core.accept(answer.words[1])
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: the snippet engine raised', notifications[1].message)
    assert.matches('boom', notifications[1].message)
  end)

  it('reports a non-function expand as the candidate being malformed, not as an engine raise', function()
    helpers.buffer({ 'fn' })

    local answer = core.complete('test', { { trigger = 'fn', expand = 'not a function' } })

    local notifications = helpers.notifications(function()
      core.accept(answer.words[1])
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: test offered a snippet with neither expand%(%) nor a string body', notifications[1].message)
  end)

  it('reports rather than silently deleting the trigger when a candidate has no expand() and no string body', function()
    helpers.buffer({ 'fn' })

    local answer = core.complete('test', { { trigger = 'fn' } })

    local notifications = helpers.notifications(function()
      core.accept(answer.words[1])
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: test offered a snippet with neither expand%(%) nor a string body', notifications[1].message)
  end)

  it('reports a raising config.options.snippets.expand instead of propagating, and leaves the trigger deleted', function()
    config.setup({
      snippets = {
        expand = function()
          error('boom')
        end,
      },
    })
    helpers.buffer({ 'local (req' })

    local answer = core.complete('test', { { trigger = 'req', body = 'require("${1}")' } })

    local notifications = helpers.notifications(function()
      core.accept(answer.words[1])
    end)

    assert.are.equal('local (', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: the snippet engine raised', notifications[1].message)
    assert.matches('boom', notifications[1].message)
  end)

  it('expands nothing it did not offer', function()
    helpers.buffer({ 'word' })

    core.complete('test', {})
    core.accept({ word = 'word', user_data = { zcmp_snip = { id = 999999 } } })

    assert.are.equal('word', vim.api.nvim_get_current_line())
  end)

  -- Vim hands a 'complete' function the `base` it captured at the first call
  -- of a cycle, and the same one again on every `refresh = 'always'` call;
  -- only the line moves on. Matching has to read the line.
  it('matches the run on the line as it is now, not as it started', function()
    local candidates = { { trigger = 'console.log' }, { trigger = 'for' } }
    helpers.buffer({ 'c' })

    local first = core.complete('test', candidates)

    vim.api.nvim_set_current_line('fo')
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    local second = core.complete('test', candidates)

    assert.are.equal('console.log', first.words[1].abbr)
    assert.are.equal(1, #second.words)
    assert.are.equal('for', second.words[1].abbr)
  end)

  it('still expands what an earlier call in the same session offered', function()
    local ran = false
    helpers.buffer({ 'fn' })

    local first = core.complete('owner-a', {
      {
        trigger = 'fn',
        expand = function()
          ran = true
        end,
      },
    })
    core.complete('owner-b', { { trigger = 'fn', body = 'other' } })
    core.accept(first.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.is_true(ran)
  end)

  it('survives a discarded completion between offering and accepting', function()
    local ran = false
    helpers.buffer({ 'fn' })

    local answer = core.complete('test', {
      {
        trigger = 'fn',
        expand = function()
          ran = true
        end,
      },
    })
    core.accept(vim.empty_dict())
    core.accept({})
    core.accept(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.is_true(ran)
  end)

  it('forgets what it offered once insert mode ends', function()
    helpers.buffer({ 'fn' })
    core.enable()

    local answer = core.complete('test', { { trigger = 'fn', body = 'x' } })
    vim.api.nvim_exec_autocmds('InsertLeave', {})
    core.accept(answer.words[1])

    assert.are.equal('fn', vim.api.nvim_get_current_line())
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

    local answer = adapter.completefunc(0)

    assert.are.equal(1, #answer.words)
    assert.are.equal('fn', answer.words[1].word)
    assert.are.equal('A function', answer.words[1].menu)
    assert.are.equal('function ${1}()\nend', answer.words[1].info)
  end)

  it('joins a table name into the description when dscr is absent', function()
    helpers.buffer({ 'fn' })
    stub_luasnip({
      { trigger = 'fn', name = { 'a', 'b' }, id = 1 },
    }, {})
    adapter.enable()

    local answer = adapter.completefunc(0)

    assert.are.equal(1, #answer.words)
    assert.are.equal('a b', answer.words[1].menu)
  end)

  it('expands the accepted snippet through luasnip, by reference', function()
    helpers.buffer({ 'fn' })
    local expanded = {}
    local snips = { { trigger = 'fn', id = 1 } }
    stub_luasnip(snips, expanded)
    adapter.enable()

    local answer = adapter.completefunc(0)
    core.accept(answer.words[1])

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

    local answer = adapter.completefunc(0)
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

    local answer = adapter.completefunc(0)
    core.accept(answer.words[1])

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal('require("${1}")', expanded)
  end)
end)
