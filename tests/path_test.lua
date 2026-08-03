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

  it('stops at max_items', function()
    local dir = tree()
    path.enable({ max_items = 2 })
    typing(dir, './')

    assert.are.equal(2, #(path.items() or {}))
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

  it('answers nothing outside a path rather than failing', function()
    typing(tree(), 'local alpha')

    assert.are.same({}, path.completefunc(0).words)
  end)

  it('names the entry that goes in complete', function()
    assert.is_true(path.source():find("zcmp.sources.path", 1, true) ~= nil)
    assert.is_nil(path.source():find(','))
  end)
end)
