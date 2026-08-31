local config = require('zcmp.config')
local fallback = require('zcmp.fallback')
local helpers = require('helpers')
local keymap = require('zcmp.keymap')

---@param bufnr integer
---@param mode string
---@param lhs string
---@return table?
local function mapping(bufnr, mode, lhs)
  local keys = vim.keycode(lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    if map.lhsraw == keys or map.lhsrawalt == keys then
      return map
    end
  end
  return nil
end

---Run what pressing `lhs` runs, without a main loop to press it in.
---@param bufnr integer
---@param mode string
---@param lhs string
local function press(bufnr, mode, lhs)
  local map = mapping(bufnr, mode, lhs)
  assert.is_not_nil(map, ('no %s mapping for %s'):format(mode, lhs))
  map.callback()
end

before_each(function()
  helpers.reset()
  helpers.mode('i')
end)
after_each(helpers.cleanup)

describe('the keymap', function()
  it('takes the named preset', function()
    config.setup({ keymap = { preset = 'enter' } })

    assert.are.same({ 'accept', 'fallback' }, keymap.resolve()['<CR>'])
    assert.are.same({ 'select_and_accept', 'fallback' }, keymap.resolve()['<C-y>'])
  end)

  -- ZCmp's own addition to blink's presets: through `fallback`, Enter reaches
  -- the feeder, which closes a menu that has nothing selected ahead of it.
  -- Unmapped, the key went straight to Vim, whose rule for the menu
  -- vim.lsp.completion rebuilds is to end completion without a newline.
  it('maps <CR> to fallback in every preset but none', function()
    for _, name in ipairs({ 'default', 'super-tab' }) do
      config.setup({ keymap = { preset = name } })
      assert.are.same({ 'fallback' }, keymap.resolve()['<CR>'], name)
    end

    config.setup({ keymap = { preset = 'enter' } })
    assert.are.same({ 'accept', 'fallback' }, keymap.resolve()['<CR>'])

    config.setup({ keymap = { preset = 'none' } })
    assert.is_nil(keymap.resolve()['<CR>'])
  end)

  it('lets an entry of its own win over the preset', function()
    config.setup({ keymap = { preset = 'enter', ['<CR>'] = { 'select_and_accept', 'fallback' } } })

    assert.are.same({ 'select_and_accept', 'fallback' }, keymap.resolve()['<CR>'])
  end)

  it('treats two spellings of one key as one entry, the user\'s spelling kept', function()
    config.setup({ keymap = { ['<C-Space>'] = { 'hide' }, ['<tab>'] = {} } })

    local resolved = keymap.resolve()
    assert.are.same({ 'hide' }, resolved['<C-Space>'])
    assert.is_nil(resolved['<C-space>'])
    assert.are.same({}, resolved['<tab>'])
    assert.is_nil(resolved['<Tab>'])
  end)

  it('maps a key once however its entry is spelled, and takes it all back', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { ['<C-Space>'] = { 'hide' }, ['<tab>'] = {} } })
    keymap.apply(bufnr)

    assert.is_nil(mapping(bufnr, 'i', '<Tab>'))
    assert.are.equal(1, #vim.tbl_filter(function(key)
      return vim.keycode(key.lhs) == vim.keycode('<C-Space>')
    end, keymap.installed(bufnr)))

    keymap.remove(bufnr)

    assert.is_nil(mapping(bufnr, 'i', '<C-Space>'))
  end)

  it('reports two spellings of one key in the keymap, and resolves the same way each time', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { ['<Tab>'] = { 'hide' }, ['<tab>'] = { 'show' } } })
    end)
    assert.is_true(helpers.notified(notified, 'spells one key twice'))

    local resolved = keymap.resolve()
    assert.are.same({ 'show' }, resolved['<tab>'])
    assert.is_nil(resolved['<Tab>'])
  end)

  it('names the same spelling as the one it keeps, in the duplicate warning and in resolve()', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { ['<C-N>'] = { 'select_prev', 'fallback' }, ['<C-n>'] = { 'select_next', 'fallback' } } })
    end)

    local winner
    for _, notification in ipairs(notified) do
      winner = tostring(notification.message):match('spells one key twice.-using %"(.-)%"$')
      if winner then
        break
      end
    end
    assert.is_not_nil(winner, 'expected a "spells one key twice" warning')

    local resolved = keymap.resolve()
    assert.is_not_nil(resolved[winner])
    for lhs in pairs(resolved) do
      if vim.keycode(lhs) == vim.keycode(winner) then
        assert.are.equal(winner, lhs)
      end
    end
  end)

  it("does not report a user entry that only spells a preset's own key differently", function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { ['<c-y>'] = { 'accept', 'fallback' } } })
    end)

    assert.is_false(helpers.notified(notified, 'spells one key twice'))
    assert.are.same({ 'accept', 'fallback' }, keymap.resolve()['<c-y>'])
    assert.is_nil(keymap.resolve()['<C-y>'])
  end)

  it('skips a keymap entry that is not a key, as config has already said', function()
    local bufnr = helpers.buffer()
    helpers.notifications(function()
      config.setup({ keymap = { 'super-tab' } })
    end)

    assert.has_no.errors(function()
      keymap.apply(bufnr)
    end)
    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
  end)

  it('skips a keymap entry that is not a key next to ones that are', function()
    helpers.notifications(function()
      config.setup({ keymap = { 'super-tab', ['<Tab>'] = { 'hide' } } })
    end)

    local resolved
    assert.has_no.errors(function()
      resolved = keymap.resolve()
    end)
    assert.are.same({ 'hide' }, resolved['<Tab>'])
  end)

  it('maps nothing under the none preset', function()
    config.setup({ keymap = { preset = 'none' } })

    assert.are.same({}, keymap.resolve())
  end)

  it('reports a preset that does not exist through setup(), and carries on with the default', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'supertab' } })
    end)

    assert.is_true(helpers.notified(notified, 'not a keymap preset'))
    assert.is_not_nil(keymap.resolve()['<C-y>'])
  end)

  it('does not notify again once resolve() runs, whatever setup() already reported', function()
    helpers.notifications(function()
      config.setup({
        keymap = {
          preset = 'supertab',
          ['<Tab>'] = { 'fallback', 'select_next' },
          ['<C-Space>'] = { 'hide' },
          ['<c-space>'] = { 'show' },
          ['<C-j>'] = { 'select_nxt', 'is_visible' },
        },
      })
    end)

    local notified = helpers.notifications(function()
      keymap.resolve()
    end)

    assert.are.same({}, notified)
  end)

  it('reports a name that is not a command through setup()', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'select_nxt' } } })
    end)

    assert.is_true(helpers.notified(notified, '<C-j> names "select_nxt", which is not a keymap command'))
  end)

  -- `zcmp.api` exports the predicates alongside the commands, and dispatch
  -- used to index the whole module: a bound predicate answered "handled" and
  -- swallowed the key, where a typo at least says so.
  it('reports a predicate through setup(), the way it reports a typo', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'is_visible' } } })
    end)

    assert.is_true(helpers.notified(notified, '<C-j> names "is_visible", which answers a question'))
    assert.is_true(helpers.notified(notified, 'not a keymap command'))
  end)

  it('does not report a function entry as a name', function()
    local notified = helpers.notifications(function()
      config.setup({
        keymap = {
          preset = 'none',
          ['<C-j>'] = {
            function()
              return true
            end,
          },
        },
      })
    end)

    assert.are.same({}, notified)
  end)

  -- `fallback` runs the mapping the key had before and ends the list, so a
  -- command written after it silently never runs.
  it('reports a command that could never run', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'fallback', 'select_next' } } })
    end)

    assert.is_true(helpers.notified(notified, 'runs nothing after'))
  end)

  it('installs its keys buffer-locally', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'enter' } })
    keymap.apply(bufnr)

    assert.is_not_nil(mapping(bufnr, 'i', '<CR>'))
    assert.is_nil(mapping(bufnr, 's', '<CR>'))
    assert.are.equal('zcmp', mapping(bufnr, 'i', '<CR>').desc)
  end)

  -- A snippet command has to reach the Select mode a placeholder puts you in.
  it('maps a snippet command in select mode too', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'snippet_forward', 'fallback' } } })
    keymap.apply(bufnr)

    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
    assert.is_not_nil(mapping(bufnr, 's', '<Tab>'))
  end)

  -- blink's rule: a function entry is opaque and may well be a snippet jump
  -- -- `if cmp.snippet_active() then return cmp.snippet_forward() end` is
  -- the usual port -- so it reaches Select mode too.
  it('maps a function entry in select mode too', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<Tab>'] = {
          function()
            return false
          end,
          'fallback',
        },
      },
    })
    keymap.apply(bufnr)

    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
    assert.is_not_nil(mapping(bufnr, 's', '<Tab>'))
  end)

  it('maps a signature command in select mode too', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' } } })
    keymap.apply(bufnr)

    assert.is_not_nil(mapping(bufnr, 'i', '<C-k>'))
    assert.is_not_nil(mapping(bufnr, 's', '<C-k>'))
  end)

  it('keeps a named entry that is neither in insert mode only', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<C-n>'] = { 'select_next', 'fallback' } } })
    keymap.apply(bufnr)

    assert.is_not_nil(mapping(bufnr, 'i', '<C-n>'))
    assert.is_nil(mapping(bufnr, 's', '<C-n>'))
  end)

  -- What makes mapping a function in Select mode safe: one that declines
  -- there hands the key to `fallback`, and with nothing else mapped the key
  -- is fed natively -- typed over the selection, as if ZCmp were not there.
  it('falls through to fallback when a function entry declines in select mode', function()
    local bufnr = helpers.buffer()
    helpers.mode('s')
    config.setup({
      keymap = {
        preset = 'none',
        ['<Tab>'] = {
          function()
            return false
          end,
          'fallback',
        },
      },
    })
    keymap.apply(bufnr)

    local fed
    local notified = helpers.notifications(function()
      fed = helpers.keys(function()
        press(bufnr, 's', '<Tab>')
      end)
    end)

    assert.are.same({ vim.keycode('<Tab>') }, fed)
    assert.are.same({}, notified)
  end)

  it('leaves a key alone when its entry is empty', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'enter', ['<CR>'] = {} } })
    keymap.apply(bufnr)

    assert.is_nil(mapping(bufnr, 'i', '<CR>'))
    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
  end)

  it('treats a keymap entry of false the same as an empty one', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'enter', ['<CR>'] = false } })

    assert.are.same({}, keymap.resolve()['<CR>'])

    keymap.apply(bufnr)
    assert.is_nil(mapping(bufnr, 'i', '<CR>'))
    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
  end)

  it("leaves a preset's own entry standing when a keymap entry is true", function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'enter', ['<CR>'] = true } })
    end)

    assert.is_true(helpers.notified(notified, 'keymap.<CR> should be table or false, got boolean'))
    assert.are.same({ 'accept', 'fallback' }, keymap.resolve()['<CR>'])
  end)

  it('runs commands in order until one handles the key', function()
    local bufnr = helpers.buffer()
    local ran = {}
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-j>'] = {
          function()
            ran[#ran + 1] = 'first'
            return false
          end,
          function(cmp)
            local is_api = type(cmp.select_next) == 'function' and cmp.reload == nil
            ran[#ran + 1] = is_api and 'second' or 'no api'
            return true
          end,
          function()
            ran[#ran + 1] = 'third'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    press(bufnr, 'i', '<C-j>')
    assert.are.same({ 'first', 'second' }, ran)
  end)

  -- blink's contract for a function entry is `fun(cmp): boolean | string |
  -- nil`: the string is keys in <Key> notation, fed as if typed -- same as
  -- blink, and same as the key it stands in for.
  it('decodes the string a function entry returns as <Key> notation', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-l>'] = {
          function()
            return '<C-n>'
          end,
          'fallback',
        },
      },
    })
    keymap.apply(bufnr)

    local fed = helpers.keys(function()
      press(bufnr, 'i', '<C-l>')
    end)

    assert.are.same({ vim.keycode('<C-n>') }, fed)
  end)

  -- Every feed carries the 'i' flag, so the two feeds one press makes -- a
  -- function entry's `hide()` and the `fallback` it falls through to -- land
  -- in the reverse of the order they were made: the <CR> ran with the menu
  -- still up, and the <C-e> after it, with no menu, was i_CTRL-E. Read
  -- backwards, the feedkeys() sequence below is `<C-e>` then `<CR>` on the
  -- queue, and one <C-e> only.
  it('feeds a function entry that hides the menu and then falls through in call order', function()
    local bufnr = helpers.buffer()
    helpers.pum({ selected = -1 })
    config.setup({
      keymap = {
        preset = 'none',
        ['<CR>'] = {
          function(cmp)
            if cmp.is_visible() then
              cmp.hide()
            end
          end,
          'fallback',
        },
      },
    })
    keymap.apply(bufnr)

    local fed = helpers.keys(function()
      press(bufnr, 'i', '<CR>')
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-e>') }, fed)
  end)

  -- The same shape one command over: `select_and_accept()` ends completion
  -- with <C-n><C-y>, not <C-e>, and the <CR> it returns needs no close either.
  it('feeds no close behind a function entry that accepts and then returns <CR>', function()
    local bufnr = helpers.buffer()
    helpers.pum({ selected = -1 })
    config.setup({
      keymap = {
        preset = 'none',
        ['<CR>'] = {
          function(cmp)
            cmp.select_and_accept()
            return '<CR>'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local fed = helpers.keys(function()
      press(bufnr, 'i', '<CR>')
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-n><C-y>') }, fed)
  end)

  it('falls through to the next command when a function entry returns an empty string', function()
    local bufnr = helpers.buffer()
    local ran = false
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-l>'] = {
          function()
            return ''
          end,
          function()
            ran = true
            return true
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local fed = helpers.keys(function()
      press(bufnr, 'i', '<C-l>')
    end)

    assert.is_true(ran)
    assert.are.same({}, fed)
  end)

  -- Regression: a raw, un-keycode()'d multibyte string fed with escape_ks =
  -- false has any embedded 0x80 byte read as K_SPECIAL, swallowing whatever
  -- follows it -- '─' (U+2500) is such a byte, its UTF-8 encoding ending in
  -- 0x80, and used to insert only 'x─'.
  it('keeps a multibyte string a function entry returns intact', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-l>'] = {
          function()
            return 'x─y'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    press(bufnr, 'i', '<C-l>')
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('x─y', vim.api.nvim_get_current_line())
  end)

  -- Regression: `['<Tab>'] = { function() return '<Tab>' end }` fed remapped
  -- lands on ZCmp's own buffer-local mapping and would run the function again
  -- without bound -- 'maxmapdepth' does not count keys fed this way. The stub
  -- below stands in for that re-entry, so a regression fails an assertion
  -- instead of hanging the suite.
  it('inserts its own key once when a function entry returns it', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<Tab>'] = {
          function()
            return '<Tab>'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local map = mapping(bufnr, 'i', '<Tab>')
    local calls = 0
    local feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys, mode)
      calls = calls + 1
      assert.is_true(calls <= 2, 'looped back into its own mapping')
      if keys == vim.keycode('<Tab>') and mode:find('m') then
        map.callback()
      end
    end
    local ok, err = pcall(map.callback)
    vim.api.nvim_feedkeys = feedkeys
    if not ok then
      error(err)
    end

    assert.are.equal(1, calls)
  end)

  -- Regression: the guard above used to check only a prefix, so
  -- `['<CR>'] = function() return '<C-g>u<CR>' end` -- the common
  -- undo-break idiom -- has its own key in the middle of the result rather
  -- than at the start, was fed remapped, and hung.
  it('inserts its own key once when a function entry returns a result containing it', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<CR>'] = {
          function()
            return '<C-g>u<CR>'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local map = mapping(bufnr, 'i', '<CR>')
    local calls = 0
    local feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys, mode)
      calls = calls + 1
      assert.is_true(calls <= 2, 'looped back into its own mapping')
      if keys == vim.keycode('<C-g>u<CR>') and mode:find('m') then
        map.callback()
      end
    end
    local ok, err = pcall(map.callback)
    vim.api.nvim_feedkeys = feedkeys
    if not ok then
      error(err)
    end

    assert.are.equal(1, calls)
  end)

  it('feeds a function entry result non-remapped when its own key is in the middle', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-l>'] = {
          function()
            return 'x<C-l>y'
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local mode
    local feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(_, m)
      mode = m
    end
    press(bufnr, 'i', '<C-l>')
    vim.api.nvim_feedkeys = feedkeys

    assert.is_nil(mode:find('m'))
  end)

  -- README.md and doc/zcmp.txt promise the commands table (`zcmp.api`), not
  -- the `zcmp` module -- so `reload` and the rest of `zcmp`'s own API are not
  -- reachable from a function keymap entry.
  it('hands a function entry the commands table, not the module', function()
    local bufnr = helpers.buffer()
    local received
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-j>'] = {
          function(cmp)
            received = cmp
            return true
          end,
        },
      },
    })
    keymap.apply(bufnr)

    press(bufnr, 'i', '<C-j>')

    assert.are.equal(require('zcmp.api'), received)
  end)

  it('skips a command that does not exist silently, and tries the next one', function()
    local bufnr = helpers.buffer()
    local ran = false
    helpers.notifications(function()
      config.setup({
        keymap = {
          preset = 'none',
          ['<C-j>'] = {
            'select_nxt',
            function()
              ran = true
              return true
            end,
          },
        },
      })
    end)
    keymap.apply(bufnr)

    local notified = helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
    assert.are.same({}, notified)
  end)

  -- A bound predicate must not answer "handled" and swallow the key: it is
  -- skipped the same as a typo, and setup() already said so.
  it('declines a predicate the way it declines a typo', function()
    local bufnr = helpers.buffer()
    local ran = false
    helpers.pum({ selected = 0 })
    helpers.notifications(function()
      config.setup({
        keymap = {
          preset = 'none',
          ['<C-j>'] = {
            'is_visible',
            function()
              ran = true
              return true
            end,
          },
        },
      })
    end)
    keymap.apply(bufnr)

    local notified = helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
    assert.are.same({}, notified)
  end)

  it('keeps going when a command raises', function()
    local bufnr = helpers.buffer()
    local ran = false
    config.setup({
      keymap = {
        preset = 'none',
        ['<C-j>'] = {
          function()
            error('boom')
          end,
          function()
            ran = true
            return true
          end,
        },
      },
    })
    keymap.apply(bufnr)

    local notified = helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
    assert.is_true(helpers.notified(notified, 'the keymap entry for <C-j> raised'))
  end)

  -- An empty lhs is a table value config validation accepts but
  -- vim.keymap.set() raises on ("Invalid (empty) LHS").
  it('installs the keys after one that fails, and tracks only those', function()
    local bufnr = helpers.buffer()
    config.setup({
      keymap = {
        preset = 'none',
        [''] = { 'fallback' },
        ['<C-j>'] = { 'fallback' },
      },
    })

    local notified = helpers.notifications(function()
      keymap.apply(bufnr)
    end)

    assert.is_not_nil(mapping(bufnr, 'i', '<C-j>'))
    assert.are.same({ { mode = 'i', lhs = '<C-j>' } }, keymap.installed(bufnr))
    assert.is_true(helpers.notified(notified, 'could not be mapped'))
  end)

  -- A raise mid-loop -- out of resolve() or fallback.capture() -- must not
  -- leave a key already mapped untracked, or remove() cannot undo it.
  it('tracks a key installed before a later one raises', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'snippet_forward', 'fallback' } } })

    local capture = fallback.capture
    local calls = 0
    helpers.stub(fallback, 'capture', function(...)
      calls = calls + 1
      if calls == 2 then
        error('boom')
      end
      return capture(...)
    end)

    local ok = pcall(keymap.apply, bufnr)

    assert.is_false(ok)
    assert.are.same({ { mode = 'i', lhs = '<Tab>' } }, keymap.installed(bufnr))

    keymap.remove(bufnr)
    assert.are.same({}, keymap.installed(bufnr))
  end)
end)

describe('fallback', function()
  it('runs the buffer-local mapping it displaced', function()
    local bufnr = helpers.buffer()
    local ran = false
    vim.keymap.set('i', '<C-j>', function()
      ran = true
    end, { buffer = bufnr })

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    press(bufnr, 'i', '<C-j>')

    assert.is_true(ran)
  end)

  -- config.lua used to merge a keymap entry's command list by index, which
  -- filled a hole the `want and 'x' or nil` idiom left with whatever the
  -- default had at that position -- here, nothing, since `<Tab>` has no
  -- default entry to fall back to -- so `ipairs` in `run()` never reached
  -- `fallback` and the key was swallowed with the menu closed.
  it('reaches fallback past a hole the want-and-or idiom left in its entry', function()
    local bufnr = helpers.buffer()
    local ran = false
    vim.keymap.set('i', '<Tab>', function()
      ran = true
    end, { buffer = bufnr })

    local want = false
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'accept', want and 'snippet_forward' or nil, 'fallback' } } })
    keymap.apply(bufnr)
    press(bufnr, 'i', '<Tab>')

    assert.is_true(ran)
  end)

  it('puts the displaced mapping back', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', '<C-o>zz', { buffer = bufnr, desc = 'mine' })

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    assert.are.equal('zcmp', mapping(bufnr, 'i', '<C-j>').desc)

    keymap.remove(bufnr)
    assert.are.equal('mine', mapping(bufnr, 'i', '<C-j>').desc)
  end)

  -- vim.keymap.set() forces noremap=true unless `remap` is given; passing
  -- `noremap` in opts, as maparg() names the field, is silently ignored.
  it('puts a recursive mapping back recursive', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<Tab>', 'X', { noremap = false })

    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    keymap.remove(bufnr)

    assert.are.equal(0, mapping(bufnr, 'i', '<Tab>').noremap)
  end)

  -- LspAttach, or a user's own on_attach, can remap the same buffer+mode+lhs
  -- after apply() ran. remove() must not treat that mapping as its own.
  it('leaves a mapping installed over it by someone else alone', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)

    local ran = false
    vim.keymap.set('i', '<C-j>', function()
      ran = true
    end, { buffer = bufnr, desc = 'someone else' })

    keymap.remove(bufnr)

    local map = mapping(bufnr, 'i', '<C-j>')
    assert.is_not_nil(map)
    assert.are.equal('someone else', map.desc)
    map.callback()
    assert.is_true(ran)
  end)

  -- An autopair plugin's <CR> is global and lands here, not in the capture.
  it('runs a global mapping when the buffer has none', function()
    local bufnr = helpers.buffer()
    local ran = false
    vim.keymap.set('i', '<C-j>', function()
      ran = true
    end)

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    press(bufnr, 'i', '<C-j>')
    vim.keymap.del('i', '<C-j>')

    assert.is_true(ran)
  end)

  it('feeds the keys of a global expr mapping', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', function()
      return '<C-o>zz'
    end, { expr = true, replace_keycodes = true })

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    local fed = helpers.keys(function()
      press(bufnr, 'i', '<C-j>')
    end)
    vim.keymap.del('i', '<C-j>')

    assert.are.same({ vim.keycode('<C-o>zz') }, fed)
  end)

  it('feeds the key itself when nothing was mapped to it', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'snippet_forward', 'fallback' } } })
    keymap.apply(bufnr)

    local fed = helpers.keys(function()
      press(bufnr, 'i', '<Tab>')
    end)

    assert.are.same({ vim.keycode('<Tab>') }, fed)
  end)

  it('answers to fallback_to_mappings as well', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'fallback_to_mappings' } } })
    keymap.apply(bufnr)

    assert.are.same({ vim.keycode('<Tab>') }, helpers.keys(function()
      press(bufnr, 'i', '<Tab>')
    end))
  end)

  it('reports the keys it installed', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'none', ['<Tab>'] = { 'snippet_forward' } } })
    keymap.apply(bufnr)

    assert.are.same({ { mode = 'i', lhs = '<Tab>' }, { mode = 's', lhs = '<Tab>' } }, keymap.installed(bufnr))

    keymap.remove(bufnr)
    assert.are.same({}, keymap.installed(bufnr))
  end)

  -- remove() used to bail on an invalid buffer before ever calling
  -- fallback.clear(), leaving its `plugged` entry behind for good. A second
  -- clear() finding nothing left to do is what "no leak" looks like from
  -- outside fallback.lua, which owns the table.
  it('clears a <script> fallback entry even for a buffer already wiped out from under it', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', 'xyz', { script = true })

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    press(bufnr, 'i', '<C-j>')
    -- Flushed like every fallback execute() test: an unflushed feed sits in
    -- typeahead across specs, since the whole suite runs in one Neovim.
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    vim.api.nvim_buf_delete(bufnr, { force = true })
    keymap.remove(bufnr)

    local deleted = {}
    local del = vim.keymap.del
    helpers.stub(vim.keymap, 'del', function(mode, ...)
      deleted[#deleted + 1] = mode
      return del(mode, ...)
    end)
    fallback.clear(bufnr)

    assert.are.same({}, deleted)
  end)
end)
