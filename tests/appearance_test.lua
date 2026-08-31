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

  it('hands back what a colourscheme defined, not what it wrote over it', function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })
    appearance.apply()

    -- ColorSchemePre, the scheme itself, ColorScheme.
    appearance.restore()
    vim.api.nvim_set_hl(0, 'PmenuKind', { link = 'Comment' })
    appearance.apply()
    appearance.restore()

    assert.are.equal('Comment', hl('PmenuKind').link)
  end)

  it('gives a scheme that leaves the groups alone nothing of its own to capture', function()
    config.setup({ appearance = { kind_hl = 'ZCmpTestKind' } })
    appearance.apply()

    appearance.restore()
    appearance.apply()
    appearance.restore()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
  end)

  it('leaves the column alone when the colour is off', function()
    config.setup({ appearance = { kind_hl = false } })

    appearance.apply()

    assert.are.equal('Pmenu', hl('PmenuKind').link)
  end)

  it('reports and leaves an unknown highlight group alone', function()
    config.setup({ appearance = { kind_hl = 'ZCmpNoSuchGroup' } })

    local notified = helpers.notifications(function()
      appearance.apply()
    end)

    assert.are.equal('Pmenu', hl('PmenuKind').link)
    assert.is_true(helpers.notified(notified, 'names no highlight group'))
  end)

  -- `reverse` swaps fg and bg at draw time, so inheriting it would paint the
  -- borrowed colour onto the background -- a solid block instead of coloured
  -- text. Neovim's own default PmenuSel sets it on both channels.
  it('carries a reversed row out rather than over', function()
    vim.api.nvim_set_hl(0, 'ZCmpKindFg', { fg = 0x00ff00, ctermfg = 10 })
    vim.api.nvim_set_hl(0, 'PmenuSel', { fg = 0x111111, bg = 0x222222, reverse = true, underline = true })
    config.setup({ appearance = { kind_hl = 'ZCmpKindFg' } })

    appearance.apply()

    local sel = hl('PmenuKindSel')
    assert.are.equal(0x00ff00, sel.fg)
    assert.is_nil(sel.reverse)
    -- The row's own foreground became the background, as the draw would have.
    assert.are.equal(0x111111, sel.bg)
    assert.is_true(sel.underline)
  end)

  it('resolves cterm reverse on its own channel', function()
    vim.api.nvim_set_hl(0, 'ZCmpKindFg', { fg = 0x00ff00, ctermfg = 10 })
    vim.api.nvim_set_hl(0, 'PmenuSel', { ctermfg = 1, ctermbg = 2, cterm = { reverse = true } })
    config.setup({ appearance = { kind_hl = 'ZCmpKindFg' } })

    appearance.apply()

    local sel = hl('PmenuKindSel')
    assert.are.equal(10, sel.ctermfg)
    assert.are.equal(1, sel.ctermbg)
    assert.is_nil((sel.cterm or {}).reverse)
  end)

  it('reports a group that exists but has nothing to borrow', function()
    vim.api.nvim_set_hl(0, 'ZCmpEmptyKind', {})
    config.setup({ appearance = { kind_hl = 'ZCmpEmptyKind' } })

    local notified = helpers.notifications(function()
      appearance.apply()
    end)

    assert.are.equal('Pmenu', hl('PmenuKind').link)
    assert.is_true(helpers.notified(notified, 'no foreground to borrow'))
  end)
end)
