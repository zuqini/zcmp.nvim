local config = require('zcmp.config')
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
    assert.are.same({ 'select_and_accept' }, keymap.resolve()['<C-y>'])
  end)

  it('lets an entry of its own win over the preset', function()
    config.setup({ keymap = { preset = 'enter', ['<CR>'] = { 'select_and_accept', 'fallback' } } })

    assert.are.same({ 'select_and_accept', 'fallback' }, keymap.resolve()['<CR>'])
  end)

  it('maps nothing under the none preset', function()
    config.setup({ keymap = { preset = 'none' } })

    assert.are.same({}, keymap.resolve())
  end)

  it('reports a preset that does not exist, and carries on with the default', function()
    local notified = helpers.notifications(function()
      config.setup({ keymap = { preset = 'supertab' } })
      assert.is_not_nil(keymap.resolve()['<C-y>'])
    end)

    assert.is_true(helpers.notified(notified, 'keymap preset'))
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

  it('leaves a key alone when its entry is empty', function()
    local bufnr = helpers.buffer()
    config.setup({ keymap = { preset = 'enter', ['<CR>'] = {} } })
    keymap.apply(bufnr)

    assert.is_nil(mapping(bufnr, 'i', '<CR>'))
    assert.is_not_nil(mapping(bufnr, 'i', '<Tab>'))
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
            ran[#ran + 1] = type(cmp.select_next) == 'function' and 'second' or 'no api'
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

  it('reports a command that does not exist, and tries the next one', function()
    local bufnr = helpers.buffer()
    local ran = false
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
    keymap.apply(bufnr)

    local notified = helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
    assert.is_true(helpers.notified(notified, 'keymap command'))
  end)

  -- `zcmp.api` exports the predicates alongside the commands, and dispatch
  -- used to index the whole module: a bound predicate answered "handled" and
  -- swallowed the key, where a typo at least says so.
  it('declines a predicate the way it declines a typo', function()
    local bufnr = helpers.buffer()
    local ran = false
    helpers.pum({ selected = 0 })
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
    keymap.apply(bufnr)

    local notified = helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
    assert.is_true(helpers.notified(notified, 'keymap command'))
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

    helpers.notifications(function()
      press(bufnr, 'i', '<C-j>')
    end)
    assert.is_true(ran)
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

  it('puts the displaced mapping back', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', '<C-o>zz', { buffer = bufnr, desc = 'mine' })

    config.setup({ keymap = { preset = 'none', ['<C-j>'] = { 'fallback' } } })
    keymap.apply(bufnr)
    assert.are.equal('zcmp', mapping(bufnr, 'i', '<C-j>').desc)

    keymap.remove(bufnr)
    assert.are.equal('mine', mapping(bufnr, 'i', '<C-j>').desc)
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
end)
