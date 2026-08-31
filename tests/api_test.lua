local api = require('zcmp.api')
local config = require('zcmp.config')
local helpers = require('helpers')

---Fires CompleteDone the way real completion does, `v:event.reason` and
---all -- `nvim_exec_autocmds()`'s own `data` opt lands in the callback's
---`args.data`, not `vim.v.event`, which is what production code reads (see
---`sources/snippets/init.lua`'s handler and `api.lua`'s `on_accept`).
---`vim.v.event` is read-only through a plain assignment; `rawset` reaches
---the same table underneath it, and reading it back afterwards sees the raw
---field just as production code's read would.
---@param reason? string Omitted for a CompleteDone with no reason at all
local function complete_done(reason)
  rawset(vim.v, 'event', reason and { reason = reason } or vim.empty_dict())
  vim.api.nvim_exec_autocmds('CompleteDone', {})
  rawset(vim.v, 'event', vim.empty_dict())
end

---Fires ModeChanged the way a mode transition does -- `pattern` here becomes
---`args.match`, the `old_mode:new_mode` string `api.lua`'s `on_accept` reads
---off it, not simulated as `v:event`. `on_accept`'s own registration is
---buffer-scoped rather than pattern-scoped, so this reaches it as long as
---the current buffer is the one it was registered against --
---`nvim_exec_autocmds()` defaults to that buffer with no `buffer` opt of its
---own.
---@param pattern string
local function mode_changed(pattern)
  vim.api.nvim_exec_autocmds('ModeChanged', { pattern = pattern })
end

---A window standing in for one of |vim.lsp.util.open_floating_preview()|'s
---floats. `focus_id` tags it the way core tags its own -- `'textDocument/hover'`
---for `vim.lsp.buf.hover()`, `'textDocument/signatureHelp'` for
---`vim.lsp.buf.signature_help()` -- so a test can hand `is_signature_visible()`
---either shape.
---@param focus_id? string
---@return integer
local function popup(focus_id)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for i = 1, 200 do
    lines[i] = 'line ' .. i
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(bufnr, false, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = 20,
    height = 5,
  })
  if focus_id then
    vim.api.nvim_win_set_var(win, focus_id, bufnr)
  end
  return win
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

    complete_done('accept')
    assert.is_true(accepted)
  end)

  -- Every other user-supplied function in this codebase is pcall'd and
  -- reported by name; a raising callback used to surface as Neovim's own
  -- autocmd traceback through zcmp's frames with no mention of what armed it.
  it('reports a raising accept callback instead of propagating', function()
    helpers.pum({ selected = 0 })

    helpers.keys(function()
      api.accept({
        callback = function()
          error('boom')
        end,
      })
    end)

    local notified = helpers.notifications(function()
      complete_done('accept')
    end)
    assert.is_true(helpers.notified(notified, 'zcmp: an accept callback raised: '))
    assert.is_true(helpers.notified(notified, 'boom'))
  end)

  -- `cmp.hide(); return cmp.accept({ callback = f })` -- hide()'s <C-e> ends
  -- the menu before accept()'s own <C-y> can, so the one CompleteDone this
  -- produces is a `cancel`, not the accept the callback is documented to run
  -- on. `on_accept()` is exercised directly here, at the reason CompleteDone
  -- actually answers with, rather than through the batching that produces it
  -- -- `fallback.batch`'s own describe block already covers the reordering.
  -- A `cancel` means this feed's own <C-y> is never coming (it is
  -- |i_CTRL-Y|, with no menu left to close and so no CompleteDone of its
  -- own), so the arm must retire right there, without running the callback
  -- -- and must not survive to be spent by whatever completes next.
  it('does not run the callback on a cancel, and does not spend itself on a later unrelated accept', function()
    helpers.pum({ selected = 0 })
    local accepted = false

    helpers.keys(function()
      api.accept({
        callback = function()
          accepted = true
        end,
      })
    end)

    complete_done('cancel')
    assert.is_false(accepted)
    assert.are.equal(0, #vim.api.nvim_get_autocmds({ group = 'zcmp', event = 'CompleteDone' }))

    -- A later, unrelated accept -- no callback requested for this one.
    complete_done('accept')
    assert.is_false(accepted)
  end)

  -- `vim.lsp.completion`'s `trigger()` fires exactly this while an accept is
  -- in flight: a `vim.fn.complete()` restart on every server response, seen
  -- as a `discard` CompleteDone with the menu still up. Routine in zcmp's
  -- default config, and not a sign the accept this callback is waiting for
  -- ever happened -- the callback must survive it and still fire on the
  -- CompleteDone that is an accept.
  it('survives an intervening discard CompleteDone and still fires on the real accept', function()
    helpers.pum({ selected = 0 })
    local calls = 0

    helpers.keys(function()
      api.accept({
        callback = function()
          calls = calls + 1
        end,
      })
    end)

    complete_done('discard')
    assert.are.equal(0, calls)

    complete_done('accept')
    assert.are.equal(1, calls)
  end)

  -- The armed autocmd must not linger forever if no accept ever comes -- it
  -- would otherwise fire for whatever completes next in the buffer. `<Esc>`
  -- fires InsertLeave after the `discard` CompleteDone it produces.
  it('gives up arming the callback once insert mode is left with no accept', function()
    helpers.pum({ selected = 0 })
    local calls = 0

    helpers.keys(function()
      api.accept({
        callback = function()
          calls = calls + 1
        end,
      })
    end)

    complete_done('discard')
    vim.api.nvim_exec_autocmds('InsertLeave', {})
    assert.are.equal(
      0,
      #vim.api.nvim_get_autocmds({ group = 'zcmp', event = { 'CompleteDone', 'InsertLeave', 'ModeChanged' } })
    )

    complete_done('accept')
    assert.are.equal(0, calls)
  end)

  -- Measured on the 0.12.0 floor: <C-c> ends completion with a `discard`
  -- CompleteDone too, but fires no InsertLeave -- only a ModeChanged out of
  -- plain insert (`i`) into Normal (`n`). InsertLeave alone would leave the
  -- arm live through a <C-c> exit; ModeChanged is the backstop that catches
  -- it.
  it('gives up arming the callback once insert mode is left via <C-c>, which fires no InsertLeave', function()
    helpers.pum({ selected = 0 })
    local calls = 0

    helpers.keys(function()
      api.accept({
        callback = function()
          calls = calls + 1
        end,
      })
    end)

    complete_done('discard')
    -- The pum's own mode ('ic') closing back to plain insert is not a real
    -- exit and must not retire the arm by itself.
    mode_changed('ic:i')
    assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = 'zcmp', event = 'ModeChanged' }))

    mode_changed('i:n')
    assert.are.equal(
      0,
      #vim.api.nvim_get_autocmds({ group = 'zcmp', event = { 'CompleteDone', 'InsertLeave', 'ModeChanged' } })
    )

    complete_done('accept')
    assert.are.equal(0, calls)
  end)

  -- Measured on the 0.12.0 floor: <Insert> then <C-c> lands in Replace mode
  -- first, so the exit is `i:R` then `R:n`, never `i:n` -- and fires no
  -- InsertLeave either. The widened `:n` suffix check is what catches this,
  -- not just plain insert's own `i:n`.
  it('gives up arming the callback on any ModeChanged into Normal, not only i:n', function()
    helpers.pum({ selected = 0 })
    local calls = 0

    helpers.keys(function()
      api.accept({
        callback = function()
          calls = calls + 1
        end,
      })
    end)

    complete_done('discard')
    mode_changed('i:R')
    assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = 'zcmp', event = 'ModeChanged' }))

    mode_changed('R:n')
    assert.are.equal(
      0,
      #vim.api.nvim_get_autocmds({ group = 'zcmp', event = { 'CompleteDone', 'InsertLeave', 'ModeChanged' } })
    )

    complete_done('accept')
    assert.are.equal(0, calls)
  end)

  -- Every arm is buffer-local, not the hand-rolled buffer comparison it
  -- replaced: wiping the arm's buffer mid-completion must reap all three
  -- autocmds, or the leaked ModeChanged compares dead buffer handles
  -- forever -- buffer handles are monotonic and never reused, so that
  -- comparison could never pass again.
  it('does not survive its buffer being wiped', function()
    helpers.pum({ selected = 0 })

    helpers.keys(function()
      api.accept({ callback = function() end })
    end)
    assert.are.equal(
      3,
      #vim.api.nvim_get_autocmds({ group = 'zcmp', event = { 'CompleteDone', 'InsertLeave', 'ModeChanged' } })
    )

    vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
    assert.are.equal(
      0,
      #vim.api.nvim_get_autocmds({ group = 'zcmp', event = { 'CompleteDone', 'InsertLeave', 'ModeChanged' } })
    )
  end)

  -- `zcmp.disable()` deletes the `zcmp` augroup by name; a callback armed
  -- through it must not outlive that, or it can fire for someone else's
  -- completion once ZCmp has let go of the buffer.
  it('arms the callback in the zcmp augroup, gone once zcmp is disabled', function()
    helpers.pum({ selected = 0 })

    helpers.keys(function()
      api.accept({ callback = function() end })
    end)
    assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = 'zcmp', event = 'CompleteDone' }))

    require('zcmp').disable()
    assert.is_false((pcall(vim.api.nvim_get_autocmds, { group = 'zcmp', event = 'CompleteDone' })))
  end)

  -- One <C-n> and nothing after it: the menu show() opens has nothing
  -- selected unless a source marked an item, the same as one that opened by
  -- itself -- a second <C-n> would select the first.
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

  -- A command answers with one boolean. The close runs under pcall, whose
  -- second value -- the message, and only on the failure this stubs in -- would
  -- otherwise ride out of a `return cmp.hide_documentation()` a user wrote.
  it("answers with one value, not pcall's two", function()
    local win = popup()
    helpers.pum({ selected = 0, preview_winid = win })
    helpers.stub(vim.api, 'nvim_win_close', function()
      error('E444: Cannot close last window')
    end)

    assert.are.equal(1, select('#', api.hide_documentation()))
    assert.is_false(api.hide_documentation())
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

  -- Without this, the shipped preset's `{ 'show_signature', 'hide_signature',
  -- 'fallback' }` can never reach `hide_signature`: `show_signature` would
  -- always answer true and re-ask for the same window instead of closing it.
  it('declines to open a second time while the window is already up, so hide_signature can close it', function()
    config.setup({ signature = { enabled = true } })
    helpers.stub(vim.lsp, 'get_clients', function()
      return { {} }
    end)
    local win = popup('textDocument/signatureHelp')
    vim.b.lsp_floating_preview = win

    assert.is_false(api.show_signature())
    assert.is_true(api.hide_signature())
  end)

  -- `open_floating_preview()` sets `lsp_floating_preview` for every caller,
  -- `vim.lsp.buf.hover()` included -- pressing `K` and then `<C-k>` must not
  -- decline to ask for signature help, nor close the hover, on that basis
  -- alone.
  it('does not decline, and does not close, a hover float', function()
    config.setup({ signature = { enabled = true } })
    helpers.stub(vim.lsp, 'get_clients', function()
      return { {} }
    end)
    helpers.stub(vim.lsp.buf, 'signature_help', function() end)
    local win = popup('textDocument/hover')
    vim.b.lsp_floating_preview = win

    assert.is_false(api.is_signature_visible())
    assert.is_true(api.show_signature())
    assert.is_false(api.hide_signature())
    assert.is_true(vim.api.nvim_win_is_valid(win))
  end)
end)
