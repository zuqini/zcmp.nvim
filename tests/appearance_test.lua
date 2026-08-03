local appearance = require('zcmp.appearance')
local config = require('zcmp.config')
local helpers = require('helpers')

---@param name string
---@return table
local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name })
end

before_each(function()
  helpers.reset()
  vim.api.nvim_set_hl(0, 'ZCmpTestKind', { fg = 0x00ff00 })
  vim.api.nvim_set_hl(0, 'Pmenu', { bg = 0x111111 })
  vim.api.nvim_set_hl(0, 'PmenuSel', { bg = 0x222222 })
  vim.api.nvim_set_hl(0, 'PmenuKind', { link = 'Pmenu' })
  vim.api.nvim_set_hl(0, 'PmenuKindSel', { link = 'PmenuSel' })
end)
after_each(helpers.cleanup)

describe('the kind column', function()
  it("borrows its colour and keeps the menu's background", function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })

    appearance.apply()

    assert.are.equal(0x00ff00, hl('PmenuKind').fg)
    assert.are.equal(0x111111, hl('PmenuKind').bg)
    assert.are.equal(0x222222, hl('PmenuKindSel').bg)
  end)

  -- |zcmp.disable()| is documented as handing everything back, and a link is
  -- what a colourscheme usually leaves these two as.
  it('is handed back as the link it was', function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })

    appearance.apply()
    appearance.restore()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
    assert.are.equal('PmenuSel', hl('PmenuKindSel').link)
  end)

  -- A second apply() in the same colourscheme must not capture what the first
  -- one wrote, or restore would hand back ZCmp's own colours.
  it('captures what was there once, not what it wrote', function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })

    appearance.apply()
    appearance.apply()
    appearance.restore()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
  end)

  it('captures again once a colourscheme has redefined the groups', function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })
    appearance.apply()

    vim.api.nvim_set_hl(0, 'PmenuKind', { link = 'Comment' })
    appearance.forget()
    appearance.apply()
    appearance.restore()

    assert.are.equal('Comment', hl('PmenuKind').link)
  end)

  it('leaves the column alone when the colour is off', function()
    config.setup({ appearance = { kind_hl = false } })

    appearance.apply()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
  end)

  it('leaves an unknown highlight group alone', function()
    config.setup({ appearance = { kind_hl = 'ZCmpNoSuchGroup' } })

    appearance.apply()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
  end)

  -- The option is a group name or false; `true` passes the shape check, and
  -- used to raise out of enable() and out of every ColorScheme after it.
  it('reports a value that is neither, rather than raising', function()
    config.setup({ appearance = { kind_hl = true } })

    local notified = helpers.notifications(function()
      assert.has_no.errors(appearance.apply)
    end)

    assert.is_true(helpers.notified(notified, 'appearance.kind_hl is a highlight group or false'))
  end)
end)
