---What `keymap.lua`'s 'fallback' describe block already exercises end to end
---(capturing a displaced mapping and running it); this covers `M.restore()`'s
---own decoding of `maparg()`'s `mode` field, one shape at a time.

local fallback = require('zcmp.fallback')
local helpers = require('helpers')

before_each(helpers.reset)
after_each(helpers.cleanup)

describe('fallback.restore', function()
  it("restores a mapping captured as mode ' ' to every mode it covers", function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, '', '<C-j>', 'gg', {})
    local captured = fallback.capture(bufnr, 'n', '<C-j>')
    assert.are.equal(' ', captured.mode)

    vim.keymap.set('n', '<C-j>', function() end, { buffer = bufnr })
    fallback.restore(bufnr, captured)

    assert.are.equal('gg', vim.fn.maparg('<C-j>', 'n'))
    assert.are.equal('gg', vim.fn.maparg('<C-j>', 'v'))
    assert.are.equal('gg', vim.fn.maparg('<C-j>', 'o'))
  end)

  it('restores a multi-letter mode mask to a mode list', function()
    local bufnr = helpers.buffer()
    vim.cmd('map <buffer> <C-l> gg')
    vim.cmd('ounmap <buffer> <C-l>')
    local captured = fallback.capture(bufnr, 'n', '<C-l>')
    assert.are.equal('nv', captured.mode)

    vim.keymap.set('n', '<C-l>', function() end, { buffer = bufnr })
    fallback.restore(bufnr, captured)

    assert.are.equal('gg', vim.fn.maparg('<C-l>', 'n'))
    assert.are.equal('gg', vim.fn.maparg('<C-l>', 'v'))
    assert.are.equal('', vim.fn.maparg('<C-l>', 'o'))
  end)

  it('restores a vmap captured under an s-mode query back under v, not s', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('v', '<C-k>', 'gg', { buffer = bufnr })
    local captured = fallback.capture(bufnr, 's', '<C-k>')
    assert.are.equal('v', captured.mode)

    vim.keymap.set('s', '<C-k>', function() end, { buffer = bufnr })
    fallback.restore(bufnr, captured)

    local restored
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 's')) do
      if vim.keycode(map.lhs) == vim.keycode('<C-k>') then
        restored = map
      end
    end

    assert.is_not_nil(restored)
    assert.are.equal('v', restored.mode)
    assert.are.equal('gg', restored.rhs)
  end)

  -- A `<script>` mapping's own `noremap` is 2, not 0 or 1 -- restoring it as
  -- `remap = true` (the old `noremap ~= 1` test) put it back fully recursive.
  it('restores a <script> mapping (noremap = 2) as script = true, not remap = true', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', 'xyz', { script = true, silent = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')
    assert.are.equal(2, captured.noremap)
    assert.are.equal(1, captured.script)

    vim.keymap.set('i', '<C-j>', function() end, { buffer = bufnr })
    fallback.restore(bufnr, captured)

    local restored
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'i')) do
      if map.lhsraw == vim.keycode('<C-j>') or map.lhsrawalt == vim.keycode('<C-j>') then
        restored = map
      end
    end

    assert.is_not_nil(restored)
    assert.are.equal(2, restored.noremap)
    assert.are.equal(1, restored.script)
  end)
end)

describe('fallback.execute', function()
  -- The 'i' feed is queued, not run; entering Insert mode and flushing are
  -- both done with a synchronous feedkeys() around it so this exercises the
  -- same key processing a real keystroke would, without a main loop.
  it("feeds a Vimscript <expr> mapping's result raw, not re-escaped through vim.keycode twice", function()
    local bufnr = helpers.buffer()
    -- What `inoremap <expr> <CR> "a\<Left>b"` stores: the expr-quote escapes
    -- stay literal text in the rhs, evaluated only when the key is pressed.
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<CR>', [["a\<Left>b"]], { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<CR>')

    fallback.run('i', '<CR>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('ba', vim.api.nvim_get_current_line())
  end)

  -- `nvim_buf_get_keymap()` hands back the rhs as typed -- bare notation,
  -- no backslash -- while `:map` ran `replace_termcodes()` on it before
  -- storing it, and evaluates that copy. Without redoing that step, this
  -- bare `"<BS>"` would reach `nvim_eval()` as the four literal characters
  -- rather than a backspace.
  it('evaluates bare <Key> notation inside a Vimscript <expr> result, not just backslash escapes', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'abc' })
    -- Column 2 ('c') is a valid Normal-mode cursor position on a 3-char
    -- line, so entering Insert mode below leaves it exactly before 'c'.
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<CR>', [[pumvisible() ? "<C-n>" : "<BS>"]], { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<CR>')

    fallback.run('i', '<CR>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('ac', vim.api.nvim_get_current_line())
  end)

  -- Native Neovim unescapes the stored rhs before evaluating and escapes
  -- the result after; a value that never went through the definition-time
  -- keycode -- a variable's -- carries a raw 0x80 that only the second step
  -- protects, while a literal's was escaped by the first and must not be
  -- escaped twice. Both shapes in one mapping pins the order.
  it('keeps a multibyte value from a variable and one from a literal alike in a Vimscript <expr> result', function()
    local bufnr = helpers.buffer()
    vim.g.zcmp_test_dash = '─'
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', [["a<Left>" . g:zcmp_test_dash . "b─c"]], { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    vim.g.zcmp_test_dash = nil
    assert.are.equal('─b─ca', vim.api.nvim_get_current_line())
  end)

  -- `<lt>` is how a mapping spells a literal `<` rather than starting a key
  -- name; `replace_termcodes()` still has to run to resolve it.
  it('inserts a literal <tab> written as <lt>tab> in a Vimscript <expr> result', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', [["<lt>tab>"]], { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('<tab>', vim.api.nvim_get_current_line())
  end)

  it('still decodes a plain rhs written in <Key> notation', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', 'x<Left>y', {})
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('yx', vim.api.nvim_get_current_line())
  end)

  -- '─' (U+2500) is a byte-for-byte regression case: its UTF-8 encoding ends
  -- in 0x80, indistinguishable from a lone K_SPECIAL byte unless escaped.
  it("feeds a Vimscript <expr> mapping's raw multibyte result without swallowing a byte", function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<CR>', [["x─y"]], { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<CR>')

    fallback.run('i', '<CR>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('x─y', vim.api.nvim_get_current_line())
  end)

  it('inserts a Number result from a Vimscript <expr> mapping, stringified', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', '42', { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('42', vim.api.nvim_get_current_line())
  end)

  it('reports a Vimscript <expr> mapping that raises, and inserts nothing', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', 'NoSuchFunction123()', { expr = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    local notifications = helpers.notifications(function()
      fallback.run('i', '<C-j>', captured)
      vim.api.nvim_feedkeys('i', 'i', false)
      vim.fn.feedkeys('', 'x')
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: the mapping for <C%-j> raised', notifications[1].message)
    assert.matches('E117', notifications[1].message)
  end)

  it('reports a raising non-expr Lua callback mapping, naming the key, and inserts nothing', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', function()
      error('boom')
    end, { buffer = bufnr })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    local notifications = helpers.notifications(function()
      fallback.run('i', '<C-j>', captured)
      vim.api.nvim_feedkeys('i', 'i', false)
      vim.fn.feedkeys('', 'x')
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: the mapping for <C%-j> raised', notifications[1].message)
    assert.matches('boom', notifications[1].message)
  end)

  it('reports a raising expr Lua callback mapping, naming the key, and inserts nothing', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', function()
      error('boom')
    end, { buffer = bufnr, expr = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    local notifications = helpers.notifications(function()
      fallback.run('i', '<C-j>', captured)
      vim.api.nvim_feedkeys('i', 'i', false)
      vim.fn.feedkeys('', 'x')
    end)

    assert.are.equal('', vim.api.nvim_get_current_line())
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    assert.matches('zcmp: the mapping for <C%-j> raised', notifications[1].message)
    assert.matches('boom', notifications[1].message)
  end)

  it('escapes a non-replace_keycodes callback result without disturbing an already-encoded key', function()
    local bufnr = helpers.buffer()
    vim.keymap.set('i', '<C-j>', function()
      return 'a' .. vim.keycode('<Left>') .. 'b─c'
    end, { buffer = bufnr, expr = true, replace_keycodes = false })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('b─ca', vim.api.nvim_get_current_line())
  end)

  -- vim-endwise's own shape: `<script>` remaps only the `<SID>`-prefixed
  -- mapping inside the rhs, so the leading <CR> stays a plain Enter. Sourced
  -- from a file so <SID> resolves to a real script id, as it would for a
  -- plugin; `<buffer>` keeps the mapping (and the cleanup) scoped to `bufnr`.
  it('runs a <script> mapping through its own <SID> target rather than inserting it as text', function()
    local bufnr = helpers.buffer()
    local path = helpers.tempdir() .. '/endwise.vim'
    helpers.write(
      path,
      table.concat({
        [[inoremap <silent> <buffer> <SID>ZcmpTestEnd <C-R>='hello'<CR>]],
        [[imap <script> <buffer> <CR> <CR><SID>ZcmpTestEnd]],
      }, '\n')
    )
    vim.cmd('source ' .. path)
    local captured = fallback.capture(bufnr, 'i', '<CR>')
    assert.are.equal(2, captured.noremap)
    assert.are.equal(1, captured.script)

    fallback.run('i', '<CR>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.same({ '', 'hello' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  -- The `<script>` route presses a `<Plug>` whose bytes never begin with
  -- <CR>, so the close `fallback.press` puts ahead of a fed <CR> (see that
  -- describe) has to be asked of the rhs behind it instead.
  local function script_cr_feeds()
    local bufnr = helpers.buffer()
    local path = helpers.tempdir() .. '/endwise-menu.vim'
    helpers.write(
      path,
      table.concat({
        [[inoremap <silent> <buffer> <SID>ZcmpTestEnd <C-R>='hello'<CR>]],
        [[imap <script> <buffer> <CR> <CR><SID>ZcmpTestEnd]],
      }, '\n')
    )
    vim.cmd('source ' .. path)
    local captured = fallback.capture(bufnr, 'i', '<CR>')
    local feedkeys = vim.api.nvim_feedkeys
    local fed = {}
    vim.api.nvim_feedkeys = function(keys, flags)
      fed[#fed + 1] = { keys, flags }
    end
    local ok, err = pcall(fallback.run, 'i', '<CR>', captured)
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)
    return fed
  end

  it('closes a menu with nothing selected ahead of a <script> mapping whose rhs begins with <CR>', function()
    helpers.pum({ selected = -1 })

    assert.are.same(
      { { vim.keycode('<Plug>(zcmp-fallback)'), 'in' }, { vim.keycode('<C-e>'), 'in' } },
      script_cr_feeds()
    )
  end)

  it('leaves a menu with a selection to the <script> mapping itself', function()
    helpers.pum({ selected = 0 })

    assert.are.same({ { vim.keycode('<Plug>(zcmp-fallback)'), 'in' } }, script_cr_feeds())
  end)

  -- A `<script><expr>` mapping's `replace_keycodes` is 0 -- legacy `:map`
  -- syntax never sets it -- so the result is real key bytes, not <Key>
  -- notation. Left absent, vim.keymap.set() defaults an expr mapping's
  -- replace_keycodes to true, and the throwaway <Plug> mapping would run
  -- those bytes through vim.keycode()'s escaping a second time.
  it("runs a <script><expr> mapping's real key bytes without re-escaping them", function()
    local bufnr = helpers.buffer()
    local path = helpers.tempdir() .. '/scriptexpr.vim'
    helpers.write(
      path,
      table.concat({
        [[function! s:ZcmpTestFn() abort]],
        [[  return "xy\<BS>z"]],
        [[endfunction]],
        [[imap <script> <buffer> <expr> <C-j> <SID>ZcmpTestFn()]],
      }, '\n')
    )
    vim.cmd('source ' .. path)
    local captured = fallback.capture(bufnr, 'i', '<C-j>')
    assert.are.equal(1, captured.expr)
    assert.are.equal(2, captured.noremap)

    fallback.run('i', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal('xz', vim.api.nvim_get_current_line())
  end)

  -- A `<script><expr>` rhs is an expression, so the menu-close question has
  -- to be asked of its value, not of the rhs; Vim evaluating it behind the
  -- `<Plug>` unseen left a leading <CR> to `compl_enter_selects`, which ended
  -- completion without a newline.
  local function script_expr_cr(tail)
    local bufnr = helpers.buffer()
    local path = helpers.tempdir() .. '/scriptexpr-cr.vim'
    helpers.write(
      path,
      table.concat({
        [[function! s:ZcmpTestTail() abort]],
        [[  let g:zcmp_test_tail_ran = get(g:, 'zcmp_test_tail_ran', 0) + 1]],
        ('  return %s'):format(tail),
        [[endfunction]],
        [[imap <script> <buffer> <expr> <CR> "\<CR>" . <SID>ZcmpTestTail()]],
      }, '\n')
    )
    vim.cmd('source ' .. path)
    vim.g.zcmp_test_tail_ran = 0
    local captured = fallback.capture(bufnr, 'i', '<CR>')
    assert.are.equal(1, captured.expr)
    assert.are.equal(1, captured.script)
    return bufnr, captured
  end

  it('closes a menu with nothing selected ahead of a <script><expr> mapping whose value begins with <CR>', function()
    local _, captured = script_expr_cr('"x"')
    helpers.pum({ selected = -1 })

    local fed = {}
    local feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys, flags)
      fed[#fed + 1] = { keys, flags }
    end
    local ok, err = pcall(fallback.run, 'i', '<CR>', captured)
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)

    assert.are.same({ { vim.keycode('<Plug>(zcmp-fallback)'), 'in' }, { vim.keycode('<C-e>'), 'in' } }, fed)
    assert.are.equal(1, vim.g.zcmp_test_tail_ran)
  end)

  it("runs a <script><expr> mapping's <SID> call and inserts its value", function()
    local bufnr, captured = script_expr_cr('"x"')

    fallback.run('i', '<CR>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    assert.are.equal(1, vim.g.zcmp_test_tail_ran)
    assert.are.same({ '', 'x' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)

describe('fallback.clear', function()
  it('removes the throwaway <Plug>(zcmp-fallback) mapping a <script> execute() left behind', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-j>', 'xyz', { script = true })
    local captured = fallback.capture(bufnr, 'i', '<C-j>')

    fallback.run('i', '<C-j>', captured)
    -- Flushed like every other execute() test: an unflushed feed sits in
    -- typeahead across specs, since the whole suite runs in one Neovim.
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    local function has_plug()
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 'i')) do
        if map.lhsraw == vim.keycode('<Plug>(zcmp-fallback)') then
          return true
        end
      end
      return false
    end
    assert.is_true(has_plug())

    local deleted = {}
    local del = vim.keymap.del
    helpers.stub(vim.keymap, 'del', function(mode, ...)
      deleted[#deleted + 1] = mode
      return del(mode, ...)
    end)

    fallback.clear(bufnr)

    assert.is_false(has_plug())
    -- Only the mode execute() actually created a mapping in -- not a second,
    -- unconditional attempt at 's', which the buffer never had one in.
    assert.are.same({ 'i' }, deleted)
  end)

  -- A <script> smap run through Select-mode fallback creates the throwaway
  -- <Plug> mapping in 's' only, with no <script> imap ever created; clear()
  -- must not guess at 'i' too.
  it('removes an s-mode-only throwaway mapping, with no <script> imap ever created', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_buf_set_keymap(bufnr, 's', '<C-j>', 'xyz', { script = true })
    local captured = fallback.capture(bufnr, 's', '<C-j>')

    fallback.run('s', '<C-j>', captured)
    vim.api.nvim_feedkeys('i', 'i', false)
    vim.fn.feedkeys('', 'x')

    local function has_plug()
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, 's')) do
        if map.lhsraw == vim.keycode('<Plug>(zcmp-fallback)') then
          return true
        end
      end
      return false
    end
    assert.is_true(has_plug())

    local deleted = {}
    local del = vim.keymap.del
    helpers.stub(vim.keymap, 'del', function(mode, ...)
      deleted[#deleted + 1] = mode
      return del(mode, ...)
    end)

    fallback.clear(bufnr)

    assert.is_false(has_plug())
    assert.are.same({ 's' }, deleted)
  end)
end)

describe('fallback.run in Select mode', function()
  local config = require('zcmp.config')
  local keymap = require('zcmp.keymap')

  ---A Select-mode selection over the line, zcmp's own s-mode <Tab> declining
  ---so the key falls through to a global vmap, and typeahead drained: what
  ---the line and the mode were afterwards, the editor put back in Normal.
  ---@param rhs string|function
  ---@param opts? table
  ---@param edit? fun() An edit to make first, so that an undo would show
  ---@return string[] lines
  ---@return string mode
  local function press_tab_over(rhs, opts, edit)
    local bufnr = helpers.buffer({ 'hello world' })
    if edit then
      edit()
    end
    vim.keymap.set('v', '<Tab>', rhs, opts)
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

    vim.api.nvim_feedkeys(vim.keycode('0gh<Tab>'), 'mx', false)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local mode = vim.fn.mode(1)

    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
    vim.keymap.del('v', '<Tab>')
    return lines, mode
  end

  -- Vim runs a Visual-mode mapping from Visual and then puts Select mode back
  -- (|Select-mode-mapping|), so the next typed key still replaces the
  -- placeholder. The <C-g> switch alone left the user in Visual, where the
  -- next typed key deletes the selection instead.
  it('restores Select mode after the Visual-mode mapping it handed the key to', function()
    local lines, mode = press_tab_over('>gv')

    assert.are.same({ '\thello world' }, lines)
    assert.are.equal('s', mode)
  end)

  -- Vim's K_SELECT behind a rhs that left Visual is `nv_select`, which
  -- reselects the same area (|Select-mode-mapping|), so `vnoremap <Tab>
  -- <Esc>` from Select ends in Select natively, with nothing to report.
  it('reselects after a mapping that left Visual, as Vim does', function()
    local lines, mode
    local notified = helpers.notifications(function()
      lines, mode = press_tab_over('<Esc>', { remap = false })
    end)

    assert.are.same({ 'hello world' }, lines)
    assert.are.equal('s', mode)
    assert.are.same({}, notified)
  end)

  -- The restore is one key, as natively: a rhs that reads a key itself (a
  -- surround prompt) consumes exactly it. A multi-key tail -- the `<Cmd>`
  -- this once fed -- leaves its remainder to run as Normal-mode commands,
  -- among them `u`, which undid the edit made before the key was pressed.
  it('hands a rhs that reads a key exactly one key, as Vim does', function()
    local got
    local lines = press_tab_over(function()
      got = vim.fn.getcharstr()
    end, nil, function()
      vim.api.nvim_feedkeys(vim.keycode('Aundoable<Esc>'), 'nx', false)
    end)

    assert.are.same({ 'hello worldundoable' }, lines)
    assert.are.equal('\128\245X', got)
  end)
end)

describe('fallback.press', function()
  -- Vim's `compl_enter_selects`: a <CR> in a menu vim.fn.complete() built
  -- with 'noinsert' and nothing selected -- the LSP restart -- ends completion
  -- without a newline, where the 'autocomplete' cycle lets the key through.
  -- The feeder closes the menu first so both agree; fed second, since the
  -- 'i' flag puts it in front of the key.
  it('closes a menu with nothing selected ahead of a fed <CR>, non-remapped', function()
    helpers.pum({ selected = -1 })
    local feedkeys = vim.api.nvim_feedkeys
    local fed = {}
    vim.api.nvim_feedkeys = function(keys, flags)
      fed[#fed + 1] = { keys, flags }
    end
    local ok, err = pcall(fallback.press, '<CR>', { remap = true })
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)

    assert.are.same({ { vim.keycode('<CR>'), 'im' }, { vim.keycode('<C-e>'), 'in' } }, fed)
  end)

  it('leaves a menu with a selection to the <CR> itself', function()
    helpers.pum({ selected = 0 })

    assert.are.same({ vim.keycode('<CR>') }, helpers.keys(function()
      fallback.press('<CR>')
    end))
  end)

  it('feeds <CR> alone when no menu is up', function()
    helpers.pum(false)

    assert.are.same({ vim.keycode('<CR>') }, helpers.keys(function()
      fallback.press('<CR>')
    end))
  end)

  it('never prefixes a key other than a leading <CR>', function()
    helpers.pum({ selected = -1 })

    assert.are.same({ vim.keycode('<Tab>') }, helpers.keys(function()
      fallback.press('<Tab>')
    end))
    assert.are.same({ vim.keycode('<C-g>u<CR>') }, helpers.keys(function()
      fallback.press('<C-g>u<CR>')
    end))
  end)
end)

describe('fallback.batch', function()
  -- Every feed carries the 'i' flag, so feedkeys() call order is the reverse
  -- of queue order: the assertions below read backwards from what will run.
  it('feeds the presses of one batch in reverse, so the i flag lands them in call order', function()
    helpers.pum(false)

    local fed = helpers.keys(function()
      fallback.batch(function()
        fallback.press('<C-e>')
        fallback.press('<CR>')
      end)
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-e>') }, fed)
  end)

  it('feeds a single press the same inside a batch as outside', function()
    helpers.pum(false)

    assert.are.same({ vim.keycode('<Tab>') }, helpers.keys(function()
      fallback.batch(function()
        fallback.press('<Tab>')
      end)
    end))
  end)

  it('feeds at once outside a batch', function()
    helpers.pum(false)
    local feedkeys = vim.api.nvim_feedkeys
    local fed = {}
    vim.api.nvim_feedkeys = function(keys)
      fed[#fed + 1] = keys
    end
    local ok, err = pcall(function()
      fallback.press('<Tab>')
      assert.are.same({ vim.keycode('<Tab>') }, fed)
    end)
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)
  end)

  it('queues the close for a <CR> with nothing selected ahead of it, as outside a batch', function()
    helpers.pum({ selected = -1 })
    local feedkeys = vim.api.nvim_feedkeys
    local fed = {}
    vim.api.nvim_feedkeys = function(keys, flags)
      fed[#fed + 1] = { keys, flags }
    end
    local ok, err = pcall(fallback.batch, function()
      fallback.press('<CR>', { remap = true })
    end)
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)

    assert.are.same({ { vim.keycode('<CR>'), 'im' }, { vim.keycode('<C-e>'), 'in' } }, fed)
  end)

  -- `hide()` then `fallback` on <CR>: the <C-e> already queued closes the
  -- menu before the <CR> arrives, and a second one would be i_CTRL-E with no
  -- menu left -- inserting the character from the line below.
  it('closes the menu once when a <C-e> is already queued ahead of the <CR>', function()
    helpers.pum({ selected = -1 })

    local fed = helpers.keys(function()
      fallback.batch(function()
        fallback.press('<C-e>', { ends_completion = true })
        fallback.press('<CR>')
      end)
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-e>') }, fed)
  end)

  -- The entry says so, not its bytes: `select_and_accept()` ends completion
  -- with <C-n><C-y>, and a match on <C-e> queued a close behind it.
  it('skips the close when a queued feed says it ends completion, whatever its keys', function()
    helpers.pum({ selected = -1 })

    local fed = helpers.keys(function()
      fallback.batch(function()
        fallback.press('<C-n><C-y>', { ends_completion = true })
        fallback.press('<CR>')
      end)
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-n><C-y>') }, fed)
  end)

  it('still closes ahead of the <CR> when the queued feed leaves the menu up', function()
    helpers.pum({ selected = -1 })

    local fed = helpers.keys(function()
      fallback.batch(function()
        fallback.press('<C-n>')
        fallback.press('<CR>')
      end)
    end)

    assert.are.same({ vim.keycode('<CR>'), vim.keycode('<C-e>'), vim.keycode('<C-n>') }, fed)
  end)

  it('flushes once, at the outermost batch', function()
    helpers.pum(false)

    local fed = helpers.keys(function()
      fallback.batch(function()
        fallback.press('a')
        fallback.batch(function()
          fallback.press('b')
        end)
        fallback.press('c')
      end)
    end)

    assert.are.same({ 'c', 'b', 'a' }, fed)
  end)

  it('flushes what was queued when the batched function raises, and re-raises', function()
    helpers.pum(false)

    local fed = helpers.keys(function()
      assert.has_error(function()
        fallback.batch(function()
          fallback.press('<Tab>')
          error('boom')
        end)
      end, 'boom')
    end)

    assert.are.same({ vim.keycode('<Tab>') }, fed)
    assert.are.same({ 'x' }, helpers.keys(function()
      fallback.press('x')
    end))
  end)
end)

-- `api.lua`'s own `pumvisible()`/`has_selection()` locals delegate to these:
-- the one home for the "menu up with nothing selected" question, on both
-- sides of the api -> fallback edge.
describe('fallback.menu_visible and fallback.has_selection', function()
  it('answer false with no menu up, whatever is "selected"', function()
    helpers.pum(false)
    assert.is_false(fallback.menu_visible())
    assert.is_false(fallback.has_selection())
  end)

  it('tell a menu with nothing selected apart from one that has', function()
    helpers.pum({ selected = -1 })
    assert.is_true(fallback.menu_visible())
    assert.is_false(fallback.has_selection())

    helpers.pum({ selected = 0 })
    assert.is_true(fallback.menu_visible())
    assert.is_true(fallback.has_selection())
  end)
end)
