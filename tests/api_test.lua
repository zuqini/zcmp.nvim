local api = require('zcmp.api')
local config = require('zcmp.config')
local helpers = require('helpers')

---A window standing in for the menu's documentation popup.
---@return integer
local function popup()
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i = 1, 200 do
    lines[i] = 'line ' .. i
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = 20,
    height = 5,
  })
end

before_each(function()
  helpers.reset()
  helpers.buffer()
  helpers.mode('i')
end)
after_each(helpers.cleanup)

describe('menu commands', function()
  it('does nothing, and says so, with no menu up', function()
    helpers.pum(false)

    local fed = helpers.keys(function()
      assert.is_false(api.select_next())
      assert.is_false(api.select_prev())
      assert.is_false(api.hide())
      assert.is_false(api.accept())
      assert.is_false(api.select_and_accept())
    end)

    assert.are.same({}, fed)
  end)

  it('steps through a menu that is up', function()
    helpers.pum({ selected = 0 })

    assert.are.same({ vim.keycode('<C-n>') }, helpers.keys(api.select_next))
    assert.are.same({ vim.keycode('<C-p>') }, helpers.keys(api.select_prev))
    assert.are.same({ vim.keycode('<C-e>') }, helpers.keys(api.hide))
  end)

  it('reports the menu', function()
    helpers.pum({ selected = 0 })
    assert.is_true(api.is_visible())
    assert.is_true(api.is_menu_visible())
  end)

  -- Nothing selected means nothing to accept, which is what leaves <CR> free
  -- to open a line.
  it('accepts only what is selected', function()
    helpers.pum({ selected = -1 })
    assert.are.same({}, helpers.keys(api.accept))

    helpers.pum({ selected = 2 })
    assert.are.same({ vim.keycode('<C-y>') }, helpers.keys(api.accept))
  end)

  it('selects first when asked to accept and nothing is selected', function()
    helpers.pum({ selected = -1 })
    assert.are.same({ vim.keycode('<C-n><C-y>') }, helpers.keys(api.select_and_accept))

    helpers.pum({ selected = 0 })
    assert.are.same({ vim.keycode('<C-y>') }, helpers.keys(api.select_and_accept))
  end)

  it('runs an accept callback once the item lands', function()
    helpers.pum({ selected = 0 })
    local accepted = false

    helpers.keys(function()
      api.accept({
        callback = function()
          accepted = true
        end,
      })
    end)
    assert.is_false(accepted)

    vim.api.nvim_exec_autocmds('CompleteDone', {})
    assert.is_true(accepted)
  end)

  it('opens the menu on request, but not when it is already up', function()
    helpers.pum(false)
    assert.are.same({ vim.keycode('<C-n>') }, helpers.keys(api.show))

    helpers.pum({ selected = 0 })
    assert.are.same({}, helpers.keys(api.show))
  end)

  it('stays out of the way outside insert mode', function()
    helpers.pum(false)
    helpers.mode('n')

    assert.are.same({}, helpers.keys(api.show))
  end)

  -- The point of the keyword guard: a <Tab> bound to this still indents.
  it('opens the menu on a keyword only', function()
    helpers.pum(false)

    helpers.buffer({ 'local re' })
    assert.are.same({ vim.keycode('<C-n>') }, helpers.keys(api.show_on_keyword))

    helpers.buffer({ '    ' })
    assert.are.same({}, helpers.keys(api.show_on_keyword))
  end)
end)

describe('snippet commands', function()
  ---@param active boolean
  ---@return integer[] directions jumped
  local function stub_snippets(active)
    local jumped = {}
    config.setup({
      snippets = {
        active = function()
          return active
        end,
        jump = function(direction)
          jumped[#jumped + 1] = direction
        end,
      },
    })
    return jumped
  end

  it('jumps only while a session is running', function()
    local jumped = stub_snippets(false)
    assert.is_false(api.snippet_forward())
    assert.is_false(api.snippet_backward())
    assert.are.same({}, jumped)

    jumped = stub_snippets(true)
    assert.is_true(api.snippet_forward())
    assert.is_true(api.snippet_backward())
    assert.are.same({ 1, -1 }, jumped)
  end)

  it('reports an active session', function()
    stub_snippets(true)
    assert.is_true(api.is_snippet_active())
    assert.is_true(api.snippet_active())
  end)

  -- <BS> over a placeholder should leave you typing in its place, which is not
  -- what Select mode does on its own.
  it('deletes a selected placeholder into insert mode', function()
    stub_snippets(true)

    helpers.mode('i')
    assert.are.same({}, helpers.keys(api.snippet_delete))

    helpers.mode('s')
    assert.are.same({ vim.keycode('<C-o>s') }, helpers.keys(api.snippet_delete))
  end)
end)

describe('documentation commands', function()
  it('reports no popup when there is none', function()
    helpers.pum({ selected = 0, preview_winid = 0 })

    assert.is_false(api.is_documentation_visible())
    assert.is_false(api.hide_documentation())
    assert.is_false(api.scroll_documentation_down())
    assert.is_false(api.scroll_documentation_up())
  end)

  it('scrolls the popup where it stands', function()
    local win = popup()
    helpers.pum({ selected = 0, preview_winid = win })

    assert.is_true(api.is_documentation_visible())
    assert.is_true(api.scroll_documentation_down())
    assert.is_true(vim.api.nvim_win_get_cursor(win)[1] > 1)

    local scrolled = vim.api.nvim_win_get_cursor(win)[1]
    assert.is_true(api.scroll_documentation_up())
    assert.is_true(vim.api.nvim_win_get_cursor(win)[1] < scrolled)
  end)

  it('takes a line count', function()
    local win = popup()
    helpers.pum({ selected = 0, preview_winid = win })

    api.scroll_documentation_down(3)
    assert.are.equal(4, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it('closes the popup', function()
    local win = popup()
    helpers.pum({ selected = 0, preview_winid = win })

    assert.is_true(api.hide_documentation())
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  -- Core opens it with the menu and offers no way to ask afterwards; the
  -- command exists so a blink keymap moves over unedited.
  it('always falls through a request to show it', function()
    local win = popup()
    helpers.pum({ selected = 0, preview_winid = win })

    assert.is_false(api.show_documentation())
  end)
end)

describe('signature commands', function()
  it('does nothing until signature help is turned on', function()
    config.setup({ signature = { enabled = false } })

    assert.is_false(api.show_signature())
  end)

  it('reports no signature window when there is none', function()
    assert.is_false(api.is_signature_visible())
    assert.is_false(api.hide_signature())
  end)
end)
