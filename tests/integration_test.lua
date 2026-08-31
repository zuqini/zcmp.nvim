local child = require('child')
local helpers = require('helpers')

local ROOT = vim.fn.getcwd()

-- Without `preselect` in 'completeopt' -- Neovim 0.12 has no such flag --
-- nothing is under the cursor while 'autocomplete' is on, so accepting what a
-- source marked takes a <C-n> first.
local SELECT = require('zcmp.buffer').can_preselect() and '' or '<C-n>'

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
        { name = 'path', keys = 'i./al', then_keys = '%s<C-y>' },
        {
          name = 'word',
          lines = { 'alphabetical', '' },
          cursor = { 2, 0 },
          keys = 'ialph',
          then_keys = '<C-n><C-y>',
        },
        { name = 'nothing', keys = 'izzq' },
      }, done)
    ]]):format(tree(), SELECT))

    -- The path source marks its first item, so <C-y> accepts it.
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
        { name = 'anchored', keys = 'ilocal f = ./al', then_keys = '%s<C-y>' },
      }, done)
    ]]):format(tree(), SELECT))

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
        { name = 'accept', keys = 'i./al', then_keys = '%s<CR>' },
        { name = 'newline', keys = 'izzq', then_keys = '<CR>x' },
      }, done)
    ]]):format(tree(), SELECT))

    assert.are.same({ '\tx' }, results.indent.lines)
    -- An item a source marked, accepted by the key bound to `accept`.
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
        { name = 'accepted', keys = 'i./al', then_keys = '%s<CR>' },
      }, done)
    ]]):format(tree(), SELECT))

    -- No menu, so <CR> reaches the mapping that was already there.
    assert.are.same({ 'zzqPAIRED' }, results.fallback.lines)
    -- A selected item, so zcmp keeps the key and the other mapping never runs.
    assert.are.same({ './alpha.txt' }, results.accepted.lines)
  end)

  -- Select mode has no smap of its own here; Vim's own rule for a mapping
  -- that is not an smap is to run it from Visual (|Select-mode-mapping|).
  -- Typing the rhs as text instead -- what a naive fallback would do -- turns
  -- '>gv' into literal characters replacing the selection.
  it('runs a Visual-mode mapping from Visual, not as typed text in Select', function()
    local results = run([[
      vim.keymap.set('v', '<Tab>', '>gv')
      require('zcmp').setup({ sources = { default = { 'buffer' } } })
      scenario({
        { name = 'indented', lines = { 'hello world' }, cursor = { 1, 0 }, keys = '0gh', then_keys = '<Tab>' },
      }, done)
    ]])

    assert.are.same({ '\thello world' }, results.indented.lines)
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

describe('a snippet source', function()
  -- v:completed_item is set for any item selected when completion ends, not
  -- only an accepted one: a discard (any non-completion key, <Esc>) must not
  -- expand what was merely under the cursor.
  it('expands only what was actually accepted, not merely discarded', function()
    local results = run([[
      require('zcmp.sources.snippets').enable()
      _G.zcmp_test_snippet = function(findstart)
        local core = require('zcmp.sources.snippets')
        if findstart == 1 then
          return core.findstart()
        end
        -- Two matches, so <C-n> highlights one rather than Vim's own
        -- "only match" shortcut completing (and ending completion) by itself.
        return core.complete('test', { { trigger = 'fn', body = 'BODY' }, { trigger = 'fnx', body = 'XBODY' } })
      end
      vim.bo.complete = 'Fv:lua.zcmp_test_snippet'
      scenario({
        { name = 'discard', keys = 'ifn<C-n>', then_keys = '(' },
        { name = 'accept', keys = 'ifn<C-n>', then_keys = '<C-y>' },
      }, done)
    ]])

    assert.are.same({ 'fn(' }, results.discard.lines)
    assert.are.same({ 'BODY' }, results.accept.lines)
  end)
end)

describe('with a language server attached', function()
  ---A server that answers `textDocument/completion` with `items` (Lua source
  ---for the list), after a short delay: enough for vim.lsp.completion's
  ---trigger() to rebuild a menu the 'complete' sources already opened.
  ---@param items string
  ---@return string
  local function server_answering(items)
    return ([[
    local function server(dispatchers)
      local closing = false
      local srv = {}
      function srv.request(method, _, callback)
        if method == 'initialize' then
          callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '.' } } } })
        elseif method == 'textDocument/completion' then
          vim.defer_fn(function()
            callback(nil, { isIncomplete = false, items = %s })
          end, 400)
        else
          callback(nil, nil)
        end
        return true, 1
      end
      function srv.notify(method)
        if method == 'exit' then dispatchers.on_exit(0, 0) end
        return true
      end
      function srv.is_closing() return closing end
      function srv.terminate() closing = true end
      return srv
    end
    ]]):format(items)
  end

  local SERVER = server_answering("{ { label = 'logger', kind = 3 } }")

  ---A snippet module on the child's runtimepath, with a trigger that crosses
  ---the keyword boundary (`<div`) and one that contains it (`console.log`).
  ---@return string rtp
  local function fake_snippets()
    local dir = helpers.tempdir()
    helpers.write(
      dir .. '/lua/zcmp_fake_snippets.lua',
      [[
        local core = require('zcmp.sources.snippets')
        local M = {}
        function M.enable() core.enable() end
        function M.completefunc(findstart)
          if findstart == 1 then return core.findstart() end
          return core.complete('fake', {
            { trigger = 'console.log', body = 'LOGBODY' },
            { trigger = '<div', body = 'DIVBODY' },
          }, {})
        end
        return M
      ]]
    )
    -- The default provider's shape, zsnip's: the same start column, the
    -- body and kept prefix riding under the module's own key, no
    -- `zcmp_start` at all, and the module's own CompleteDone handler
    -- expanding what was accepted.
    helpers.write(
      dir .. '/lua/zcmp_fake_keyless.lua',
      [[
        local SNIPPETS = { { trigger = 'console.log', body = 'LOGBODY' }, { trigger = '<div', body = 'DIVBODY' } }
        local M = {}
        function M.completefunc(findstart)
          local col = vim.api.nvim_win_get_cursor(0)[2]
          local before = vim.api.nvim_get_current_line():sub(1, col)
          local start = before:find('%S+$')
          if findstart == 1 then return (start or col + 1) - 1 end
          local run = start and before:sub(start) or ''
          if run == '' and vim.o.autocomplete then return { words = {}, refresh = 'always' } end
          local items = {}
          for _, snippet in ipairs(SNIPPETS) do
            for i = 1, #run do
              if vim.startswith(snippet.trigger, run:sub(i)) then
                local kept = run:sub(1, i - 1)
                items[#items + 1] = {
                  word = kept .. snippet.trigger,
                  abbr = snippet.trigger,
                  user_data = { fake = { body = snippet.body, keep = #kept } },
                }
                break
              end
            end
          end
          return { words = items, refresh = 'always' }
        end
        function M.enable()
          local group = vim.api.nvim_create_augroup('zcmp_fake_keyless', { clear = true })
          vim.api.nvim_create_autocmd('CompleteDone', {
            group = group,
            callback = function()
              if vim.v.event.reason ~= 'accept' then return end
              local completed = vim.v.completed_item
              local data = vim.tbl_get(completed or {}, 'user_data', 'fake')
              if type(data) ~= 'table' then return end
              local row, col = unpack(vim.api.nvim_win_get_cursor(0))
              local start = col - #completed.word + data.keep
              if start < 0 or start >= col then return end
              vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, col, { data.body })
              vim.api.nvim_win_set_cursor(0, { row, start + #data.body })
            end,
          })
        end
        return M
      ]]
    )
    return dir
  end

  -- trigger() takes every item on screen and re-`complete()`s it at one
  -- column, the keyword boundary, so an item whose findstart was elsewhere
  -- lands after its own head: `console.console.log`, `x<x<div`,
  -- `./sub/./sub/alpha.txt`. Each item records its start and ZCmp's own
  -- CompleteDone handler trims the head back; these are the same three runs
  -- without a client, which `sources.trim_head()` must reproduce with one.
  it('accepts a snippet or path item at the column its source chose', function()
    local dir = tree()
    helpers.write(dir .. '/sub/alpha.txt')
    local results = run(SERVER .. ([[
      vim.opt.runtimepath:prepend(%q)
      require('zcmp').setup({
        sources = {
          default = { 'lsp', 'path', 'snip' },
          providers = { snip = { module = 'zcmp_fake_snippets' } },
        },
      })
      vim.cmd('edit %s/main.txt')
      vim.lsp.start({ name = 'fake', cmd = server, root_dir = %q }, { bufnr = 0 })

      -- Not scenario(): whether the first item is already under the cursor
      -- depends on the binary (|zcmp-preselect|) and on what the restart
      -- kept, so which key accepts it is decided per step, at the time.
      local steps = {
        { name = 'snippet', keys = 'iconsole.l' },
        { name = 'boundary', keys = 'ix<di' },
        { name = 'path', keys = 'ix ./sub/al' },
      }
      local index = 0
      local function next_step()
        index = index + 1
        local step = steps[index]
        if not step then return done() end
        feed('<Esc>')
        vim.defer_fn(function()
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          feed(step.keys)
          vim.defer_fn(function()
            local result = { offered = offered(), clients = #vim.lsp.get_clients({ bufnr = 0 }) }
            local selected = vim.fn.complete_info({ 'selected' }).selected
            feed((selected >= 0 and '' or '<C-n>') .. '<C-y><Esc>')
            vim.defer_fn(function()
              result.lines = lines()
              emit(step.name, result)
              next_step()
            end, 300)
          end, 1500)
        end, 150)
      end
      vim.defer_fn(next_step, 300)
    ]]):format(fake_snippets(), dir, dir))

    -- The server's own item in the menu is the proof the restart happened.
    assert.are.equal(1, results.snippet.clients)
    assert.contains(results.snippet.offered, 'console.log')
    assert.contains(results.snippet.offered, 'logger')
    assert.are.same({ 'LOGBODY' }, results.snippet.lines)

    assert.are.equal(1, results.boundary.clients)
    assert.contains(results.boundary.offered, 'x<div')
    assert.are.same({ 'xDIVBODY' }, results.boundary.lines)

    assert.are.equal(1, results.path.clients)
    assert.contains(results.path.offered, './sub/alpha.txt')
    assert.are.same({ 'x ./sub/alpha.txt' }, results.path.lines)
  end)

  -- The restart places the server's own items, so `trim_head()` has nothing
  -- to undo for them -- and a server's word need not be keyword characters
  -- (lua_ls's `callSnippet`, clangd's `->foo`), so the head read off the text
  -- would take the `print(` typed around it.
  it('accepts a server item inside a typed call without trimming the call', function()
    local dir = tree()
    local results = run(
      server_answering("{ { label = 'print(...)', insertText = 'print(...)', insertTextFormat = 1, kind = 3 } }")
        .. ([[
      require('zcmp').setup({
        sources = { default = { 'lsp' } },
      })
      vim.cmd('edit %s/main.lua')
      vim.lsp.start({ name = 'fake', cmd = server, root_dir = %q }, { bufnr = 0 })

      vim.defer_fn(function()
        feed('iprint(pri')
        vim.defer_fn(function()
          local result = { offered = offered(), clients = #vim.lsp.get_clients({ bufnr = 0 }) }
          local selected = vim.fn.complete_info({ 'selected' }).selected
          feed((selected >= 0 and '' or '<C-n>') .. '<C-y><Esc>')
          vim.defer_fn(function()
            result.lines = lines()
            emit('nested', result)
            done()
          end, 300)
        end, 1500)
      end, 300)
    ]]):format(dir, dir)
    )

    assert.are.equal(1, results.nested.clients)
    assert.contains(results.nested.offered, 'print(...)')
    assert.are.same({ 'print(print(...)' }, results.nested.lines)
  end)

  -- The default provider, zsnip, records no `zcmp_start` -- coordination
  -- flows one way -- so the head is read off the text instead. Its own
  -- CompleteDone handler deletes `#word - keep` bytes before the cursor,
  -- which is right only once ZCmp's has trimmed the head: the module's is
  -- installed by its `enable()`, after ZCmp's on the first enable, and the
  -- order after a `reload()` -- which runs `enable()` again -- is the thing
  -- to pin.
  it('accepts a snippet item that recorded no start, before and after a reload', function()
    local dir = tree()
    local results = run(SERVER .. ([[
      vim.opt.runtimepath:prepend(%q)
      require('zcmp').setup({
        sources = {
          default = { 'lsp', 'snip' },
          providers = { snip = { module = 'zcmp_fake_keyless' } },
        },
      })
      vim.cmd('edit %s/main.txt')
      vim.lsp.start({ name = 'fake', cmd = server, root_dir = %q }, { bufnr = 0 })

      local steps = {
        { name = 'snippet', keys = 'iconsole.l' },
        { name = 'boundary', keys = 'ix<di' },
        { name = 'snippet_reloaded', keys = 'iconsole.l', before = require('zcmp').reload },
        { name = 'boundary_reloaded', keys = 'ix<di' },
      }
      local index = 0
      local function next_step()
        index = index + 1
        local step = steps[index]
        if not step then return done() end
        feed('<Esc>')
        vim.defer_fn(function()
          if step.before then step.before() end
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          feed(step.keys)
          vim.defer_fn(function()
            local result = { offered = offered(), clients = #vim.lsp.get_clients({ bufnr = 0 }) }
            local selected = vim.fn.complete_info({ 'selected' }).selected
            feed((selected >= 0 and '' or '<C-n>') .. '<C-y><Esc>')
            vim.defer_fn(function()
              result.lines = lines()
              emit(step.name, result)
              next_step()
            end, 300)
          end, 1500)
        end, 150)
      end
      vim.defer_fn(next_step, 300)
    ]]):format(fake_snippets(), dir, dir))

    for _, name in ipairs({ 'snippet', 'snippet_reloaded' }) do
      assert.are.equal(1, results[name].clients, name)
      assert.contains(results[name].offered, 'console.log', name)
      assert.contains(results[name].offered, 'logger', name)
      assert.are.same({ 'LOGBODY' }, results[name].lines, name)
    end
    for _, name in ipairs({ 'boundary', 'boundary_reloaded' }) do
      assert.are.equal(1, results[name].clients, name)
      assert.contains(results[name].offered, 'x<div', name)
      assert.are.same({ 'xDIVBODY' }, results[name].lines, name)
    end
  end)

  -- The restart builds its menu through vim.fn.complete(), which selects its
  -- first item unless 'noselect' is set -- 'autocomplete' forces the flag for
  -- its own menus, complete() does not -- so a <CR> bound to `accept` took
  -- an item nothing had marked, on both binaries, and only once the server
  -- had answered. With the flag written, <CR> means what it means without a
  -- client. `fallback` closes the menu first: Vim's own rule for a
  -- complete()-built menu with 'noinsert' and nothing selected is to end
  -- completion without a newline -- which is why every preset but `none`
  -- maps <CR> to it. The `default` preset once left the key unmapped, and
  -- the first Enter over a server item closed the menu instead of opening a
  -- line.
  -- vim.lsp.completion reaches the (widened) trigger list only after
  -- `if vim.fn.pumvisible() ~= 0 then return end`, and `trigger()` carries the
  -- same guard -- so a server that answers `isIncomplete = false` is asked
  -- once and never again while a menu is up. With 'autocompletedelay' at 0,
  -- zcmp's own sources hold one up from the first keystroke, which used to
  -- mean the server's single answer was the one for that first character.
  -- `retrigger` is what asks again; this server names the prefix it was asked
  -- for, so the menu says which ask the items came from.
  local NAMING_SERVER = [[
    local function server(dispatchers)
      local closing = false
      local srv = {}
      function srv.request(method, _, callback)
        if method == 'initialize' then
          callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '.' } } } })
        elseif method == 'textDocument/completion' then
          local col = vim.api.nvim_win_get_cursor(0)[2]
          local leader = vim.api.nvim_get_current_line():sub(1, col)
          vim.defer_fn(function()
            callback(nil, { isIncomplete = false, items = { { label = 'srv_' .. leader, kind = 1 } } })
          end, 50)
        else
          callback(nil, nil)
        end
        return true, 1
      end
      function srv.notify(method)
        if method == 'exit' then dispatchers.on_exit(0, 0) end
        return true
      end
      function srv.is_closing() return closing end
      function srv.terminate() closing = true end
      return srv
    end
  ]]

  ---Types `abc` one character at a time, letting the menu settle between
  ---each -- not `scenario()`, which feeds a step's keys in one burst: typed
  ---that way the leader is already `abc` before any menu exists, so the
  ---server's first and only ask is for `abc` and the two configurations
  ---cannot be told apart.
  ---@param provider string The `lsp` provider table to configure with
  ---@return table
  local function typed_abc(provider)
    local dir = tree()
    -- `abcxyz` in the buffer keeps core's own menu up the whole way, which is
    -- exactly the condition that locks the server out.
    return run(NAMING_SERVER .. ([[
      require('zcmp').setup({
        sources = { default = { 'lsp', 'buffer' }, providers = { lsp = %s } },
      })
      vim.cmd('edit %s/main.txt')
      vim.lsp.start({ name = 'fake', cmd = server, root_dir = %q }, { bufnr = 0 })

      vim.defer_fn(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abcxyz', '' })
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        feed('i')
        local chars, index = { 'a', 'b', 'c' }, 0
        local function tick()
          index = index + 1
          if not chars[index] then
            emit('typed', { offered = offered(), lines = lines() })
            return done()
          end
          feed(chars[index])
          vim.defer_fn(tick, 500)
        end
        vim.defer_fn(tick, 300)
      end, 500)
    ]]):format(provider, dir, dir))
  end

  it('asks the server again as the word grows', function()
    local results = typed_abc('{}')

    assert.contains(results.typed.offered, 'abcxyz')
    assert.contains(results.typed.offered, 'srv_abc')
  end)

  it('asks once, at the keystroke that opened the menu, with retrigger off', function()
    local results = typed_abc('{ opts = { retrigger = false } }')

    assert.contains(results.typed.offered, 'abcxyz')
    assert.is_false(
      vim.tbl_contains(results.typed.offered, 'srv_abc'),
      'the server was re-asked with retrigger off: ' .. vim.inspect(results.typed.offered)
    )
  end)

  describe('a server item nothing marked', function()
    local TWO = server_answering("{ { label = 'logger', kind = 3 }, { label = 'logout', kind = 3 } }")

    ---@param keymap string The `keymap` table's Lua source
    ---@return table
    local function typed_cr(keymap)
      local dir = helpers.tempdir()
      return run(TWO .. ([[
        require('zcmp').setup({
          keymap = %s,
          sources = { default = { 'lsp', 'buffer' } },
          })
        vim.cmd('edit %s/main.txt')
        vim.lsp.start({ name = 'fake', cmd = server, root_dir = %q }, { bufnr = 0 })
        scenario({
          { name = 'cr', keys = 'ilog', delay = 1500, then_keys = '<CR>' },
        }, done)
      ]]):format(keymap, dir, dir))
    end

    it('is left alone by <CR>, which opens a line', function()
      local results = typed_cr("{ preset = 'enter' }")

      -- The server's items in the menu are the proof the restart happened.
      assert.contains(results.cr.offered, 'logger')
      assert.contains(results.cr.offered, 'logout')
      assert.are.same({ 'log', '' }, results.cr.lines)
    end)

    it('is left alone by <CR> under the default preset too', function()
      local results = typed_cr("{ preset = 'default' }")

      assert.contains(results.cr.offered, 'logger')
      assert.contains(results.cr.offered, 'logout')
      assert.are.same({ 'log', '' }, results.cr.lines)
    end)

    it('is taken by <CR> bound to select_and_accept', function()
      local results = typed_cr("{ preset = 'enter', ['<CR>'] = { 'select_and_accept', 'fallback' } }")

      assert.contains(results.cr.offered, 'logger')
      assert.are.same({ 'logger' }, results.cr.lines)
    end)
  end)
end)
