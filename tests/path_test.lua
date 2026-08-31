local helpers = require('helpers')
local path = require('zcmp.sources.path')

---A buffer inside `dir`, holding `line` with the cursor after it — where it
---sits in insert mode, the only mode this source ever runs in. Normal mode
---clamps that column back one, which shortens the token under test.
---@param dir string
---@param line string
---@return integer
local function typing(dir, line)
  return helpers.buffer({ line }, dir .. '/main.lua')
end

---@return string dir
local function tree()
  local dir = helpers.tempdir()
  helpers.write(dir .. '/alpha.txt')
  helpers.write(dir .. '/alps.txt')
  helpers.write(dir .. '/beta.txt')
  helpers.write(dir .. '/sub/nested.txt')
  return dir
end

---A tree like `tree()`, but the buffer's own directory has `name` as its
---last path segment -- glob metacharacters there must not reach getcompletion().
---@param name string
---@return string dir
local function tree_named(name)
  local dir = helpers.tempdir() .. '/' .. name
  helpers.write(dir .. '/alpha.txt')
  helpers.write(dir .. '/sub/nested.txt')
  return dir
end

---@param items lsp.CompletionItem[]?
---@return string[]
local function labels(items)
  return vim.tbl_map(function(item)
    return item.label
  end, items or {})
end

before_each(function()
  helpers.reset()
  helpers.stub(vim.o, 'virtualedit', 'onemore')
  path.enable({})
end)
after_each(function()
  path.enable({})
  helpers.cleanup()
end)

describe('the path source', function()
  it('reports where the path token starts', function()
    typing(tree(), 'local f = ./al')

    assert.are.equal(10, path.start())
  end)

  it('is not in a path when the token has no slash', function()
    typing(tree(), 'local alpha')

    assert.is_nil(path.start())
    assert.is_nil(path.items())
  end)

  -- A comment marker, a division and a url scheme all put a '/' in the line
  -- without putting the cursor in a path.
  it('leaves comment markers, division and url schemes alone', function()
    local dir = tree()
    for i, line in ipairs({ '-- // note', 'local x = a / ', 'local x = a /', 'https://example.com/a' }) do
      helpers.buffer({ line }, ('%s/main%d.lua'):format(dir, i))
      assert.is_nil(path.start(), line)
    end
  end)

  -- The division guard is a bare '/' and nothing else: every root-level path
  -- starts with the same character, and rejecting the whole of '/' made them
  -- all unreachable until a second directory had been typed in full.
  it('completes a path at the filesystem root', function()
    local dir = tree()
    helpers.buffer({ dir:sub(1, 2) }, dir .. '/main.lua')

    assert.are.equal(0, path.start())
    assert.is_true(#(path.items() or {}) > 0)
  end)

  -- vim.fs.dirname() of a url answers with the scheme, and every listing off
  -- that root is empty. The cwd is the only directory such a buffer has.
  it('falls back to the cwd in a buffer a plugin backs', function()
    helpers.buffer({ './lu' }, 'oil://' .. tree())

    assert.are.same({ './lua/' }, labels(path.items()))
  end)

  it('lists the buffer directory for a relative token, not the cwd', function()
    local dir = tree()
    typing(dir, './al')

    assert.are.same({ './alpha.txt', './alps.txt' }, labels(path.items()))
  end)

  it('lists an absolute token as written', function()
    local dir = tree()
    typing(dir, dir .. '/be')

    assert.are.same({ dir .. '/beta.txt' }, labels(path.items()))
  end)

  -- vim.fs.normalize() env-expands inside a '~/' token by default, so a '$'
  -- there used to be expanded while one behind './' or '/' stays literal --
  -- one rule for the token, not two.
  it('does not env-expand a literal $ behind a ~/ token', function()
    local home = helpers.tempdir()
    helpers.write(home .. '/$ZZDIR/alpha.txt')
    helpers.stub(vim.uv, 'os_homedir', function()
      return home
    end)
    vim.env.ZZDIR = 'somewhere-else'

    typing(tree(), '~/$ZZDIR/al')
    local items = path.items()

    vim.env.ZZDIR = nil
    assert.are.same({ '~/$ZZDIR/alpha.txt' }, labels(items))
  end)

  it('marks a directory as one, and keeps its trailing slash', function()
    local dir = tree()
    typing(dir, './su')

    local items = path.items() or {}
    assert.are.equal(1, #items)
    assert.are.equal('./sub/', items[1].label)
    assert.are.equal(vim.lsp.protocol.CompletionItemKind.Folder, items[1].kind)
  end)

  it('descends into a directory that has been typed', function()
    local dir = tree()
    typing(dir, './sub/')

    assert.are.same({ './sub/nested.txt' }, labels(path.items()))
  end)

  -- getcompletion() answers a bare '.' with './' and '../' ahead of the
  -- dotfiles; neither completes anything past what was typed.
  it('lists dotfiles for a bare dot without the . and .. pseudo-entries', function()
    local dir = tree()
    helpers.write(dir .. '/.cfg')
    typing(dir, './.')

    assert.are.same({ './.cfg' }, labels(path.items()))
  end)

  it('still offers the parent directory for a typed ..', function()
    local dir = tree()
    typing(dir, './..')

    assert.are.same({ './../' }, labels(path.items()))
  end)

  it('lists dotfiles for a bare dot inside a subdirectory', function()
    local dir = tree()
    helpers.write(dir .. '/sub/.cfg')
    typing(dir, 'sub/.')

    assert.are.same({ 'sub/.cfg' }, labels(path.items()))
  end)

  it('lists a relative token when the buffer directory has a bracket glob', function()
    local dir = tree_named('[slug]')
    typing(dir, './al')

    assert.are.same({ './alpha.txt' }, labels(path.items()))
  end)

  it('lists a relative token when the buffer directory has a brace glob', function()
    local dir = tree_named('{a,b}')
    typing(dir, './al')

    assert.are.same({ './alpha.txt' }, labels(path.items()))
  end)

  it('descends into a subdirectory when the buffer directory has a bracket glob', function()
    local dir = tree_named('[slug]')
    typing(dir, './sub/')

    assert.are.same({ './sub/nested.txt' }, labels(path.items()))
  end)

  -- getcompletion() env-expands '$' inside the *segment*, not just the
  -- directory: an unescaped '$f' would resolve to nothing and list the bare
  -- directory instead. addstar() also refuses the trailing '*' whenever the
  -- tail holds a '$', escaped or not, so this only lists at all once the '*'
  -- is added explicitly.
  it('lists a literal $-prefixed file rather than env-expanding the segment', function()
    local dir = tree()
    helpers.write(dir .. '/$fx.txt')
    typing(dir, './$f')

    assert.are.same({ './$fx.txt' }, labels(path.items()))
  end)

  it('lists files in a directory named with a backtick', function()
    local dir = tree_named('a`b')
    typing(dir, './al')

    assert.are.same({ './alpha.txt' }, labels(path.items()))
  end)

  it('stops at limit', function()
    local dir = tree()
    path.enable({ limit = 2 })
    typing(dir, './')

    assert.are.equal(2, #(path.items() or {}))
  end)

  -- A bad opts.limit used to reach `#items >= limit` and raise "attempt to
  -- compare string with number" on every keystroke inside a path token.
  for _, case in ipairs({ '10', 0 }) do
    it(('falls back to the default limit and warns for %s'):format(vim.inspect(case)), function()
      local dir = tree()
      path.enable({ limit = case })

      local items
      local notified = helpers.notifications(function()
        typing(dir, './al')
        items = path.items()
      end)

      assert.are.same({ './alpha.txt', './alps.txt' }, labels(items))
      assert.are.equal(1, #notified)
      -- The dotted module name, not the leaf 'path': notify_once dedups on
      -- the message, so a shortened label would collide with a third-party
      -- module also reporting 'path opts.limit'.
      assert.is_true(helpers.notified(notified, 'zcmp.sources.path opts.limit'))
    end)
  end

  -- split() only scans the last 256 bytes of the line; a token longer than
  -- that would otherwise answer with a column in its middle and a bogus
  -- relative dir, rather than admitting the cursor is not in a path it can
  -- complete.
  it('declines a token longer than the scan window', function()
    typing(tree(), './' .. ('a'):rep(255))

    assert.is_nil(path.start())
  end)

  it('still answers just under the scan window', function()
    typing(tree(), './' .. ('a'):rep(253))

    assert.are.equal(0, path.start())
  end)

  -- -3 would leave completion mode, taking the other sources with it.
  it('answers findstart with -2 outside a path', function()
    typing(tree(), 'local alpha')

    assert.are.equal(-2, path.completefunc(1))
  end)

  it('answers in complete-items shape', function()
    local dir = tree()
    typing(dir, './al')

    local result = path.completefunc(0)
    assert.are.equal('always', result.refresh)
    assert.are.same({ './alpha.txt', './alps.txt' }, vim.tbl_map(function(word)
      return word.word
    end, result.words))
    assert.are.equal('File', result.words[1].kind)
    -- 'autocomplete' forces 'noselect', so the first item has to ask.
    assert.are.equal(1, result.words[1].preselect)
    assert.is_nil(result.words[2].preselect)
  end)

  -- Every item says where its `word` replaces from, so ZCmp's CompleteDone
  -- handler can put the token back after vim.lsp.completion re-inserts the
  -- item at the keyword boundary instead.
  it('records where the token starts on each item', function()
    typing(tree(), 'local f = ./al')

    local result = path.completefunc(0)

    assert.are.equal(2, #result.words)
    assert.are.equal(10, result.words[1].user_data.zcmp_start)
    assert.are.equal(10, result.words[2].user_data.zcmp_start)
  end)

  it('answers nothing outside a path rather than failing', function()
    typing(tree(), 'local alpha')

    assert.are.same({}, path.completefunc(0).words)
  end)

end)
