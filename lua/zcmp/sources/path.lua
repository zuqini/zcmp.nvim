---Filesystem paths, as a 'complete' function source.
---
---```lua
---require('zcmp').setup({ sources = { default = { 'path' } } })
---```
---
---The listing itself is |getcompletion()|'s: it appends `/` to directories,
---hides dotfiles until one is asked for and expands `~/`. What is left is
---finding where a path token starts in a line, which takes a cursor and so
---cannot be asked of it.

local sources = require('zcmp.sources')

-- The chunk's own module name, handed to it as `...` by `require` (Lua 5.1
-- manual §8.1) -- matches the string below without one going stale on rename.
local OWNER = ... or 'zcmp.sources.path'

local api = vim.api
local Kind = vim.lsp.protocol.CompletionItemKind

---Longest path token recognised, and the bound on `split`'s scan.
local MAX_TOKEN = 256

---getcompletion() has no limit of its own; a wide directory answers with all of it.
local DEFAULT_LIMIT = 250

local M = {}

---@class zcmp.PathOpts
---@field limit? integer Cap on entries listed per request (default 250)

---@type zcmp.PathOpts
local options = {}

local function before_cursor()
  return api.nvim_get_current_line():sub(1, api.nvim_win_get_cursor(0)[2])
end

---Relative tokens anchor to the buffer's directory; getcompletion() resolves
---against cwd alone. Keeps the trailing '/' for the caller to concatenate onto.
---@param dir string ends in '/'
---@return string? dir resolved, ending in '/'
local function resolve_dir(dir)
  if vim.startswith(dir, '/') then
    return dir
  elseif vim.startswith(dir, '~/') then
    -- expand_env defaults on, which would expand a literal '$' behind '~/'
    -- while the relative branch below leaves one behind '/' alone -- one
    -- rule for the token, not two.
    return vim.fs.normalize(dir, { expand_env = false }) .. '/'
  end

  local name = api.nvim_buf_get_name(0)
  -- A buffer a plugin backs rather than a file ('oil://', 'term://') has no
  -- directory to be relative to, and vim.fs.dirname would answer with a root
  -- made out of the scheme.
  if name:find('^%a[%w+.%-]*://') then
    name = ''
  end
  local root = name ~= '' and vim.fs.dirname(name) or vim.uv.cwd()
  return root and root .. '/' .. dir or nil
end

local TOKEN_CLASS = '[%w%._%-%+@~$/\128-\255]'

---Splits the path token into a directory to list and a segment to match. The
---character class also keeps globs out of getcompletion(); \128-\255 admits
---multibyte components. Only the last MAX_TOKEN bytes are scanned: a '$'-anchored
---run restarts at every position, and the class covers the base64 alphabet, so a
---long data URI would otherwise cost milliseconds per keystroke.
---@param before string
---@return string? dir ends in '/'
---@return string? segment possibly empty
local function split(before)
  local token = before:sub(-MAX_TOKEN):match(TOKEN_CLASS .. '*$')
  -- A token exactly MAX_TOKEN bytes long, preceded by another byte of the same
  -- class, is longer than what was scanned: its true start lies outside the
  -- window, so a column answered here would land in the middle of the token.
  if #token == MAX_TOKEN and before:sub(-MAX_TOKEN - 1, -MAX_TOKEN - 1):match(TOKEN_CLASS) then
    return nil
  end
  local dir = token:match('^(.*/)')
  -- A comment marker ('-- //') or a url scheme ('https://') puts a '/' in the
  -- line without putting the cursor in a path.
  if not dir or dir:find('//', 1, true) then
    return nil
  end
  local segment = token:sub(#dir + 1)
  -- A bare '/' with nothing yet typed after it is a division ('x = a /'). A
  -- root-level path is the same token plus a character, so this costs one
  -- keystroke and nothing else.
  if dir == '/' and segment == '' then
    return nil
  end
  return dir, segment
end

---@return integer? col 0-based start of the path token, nil outside one
function M.start()
  local before = before_cursor()
  local dir, segment = split(before)
  return dir and #before - #dir - #segment or nil
end

---Path candidates for the cursor position.
---
---Derived from the live line rather than the 'complete' function's `base`,
---which is frozen at the first call of a cycle and goes stale the moment you
---type.
---@return lsp.CompletionItem[]? items nil when the cursor is not inside a path
function M.items()
  local dir, segment = split(before_cursor())
  if not dir then
    return nil
  end

  local root = resolve_dir(dir)
  if not root then
    return nil
  end

  local limit = sources.limit(options, DEFAULT_LIMIT, OWNER)
  local items = {}
  -- The whole token is data, not a pattern -- the buffer's directory and
  -- what the user typed alike: escape both so a literal '[slug]', '{a,b}' or
  -- '$HOME' anywhere in it is not read as a glob or expanded as an
  -- environment variable. getcompletion() answers with the unescaped path,
  -- so root (unescaped) is still the right prefix to strip below.
  --
  -- The trailing '*' is explicit rather than left to addstar(): Neovim
  -- refuses to append it whenever the tail contains '$' or a backtick, even
  -- escaped, so an escaped '\$f' alone lists nothing -- only '\$f*' lists
  -- '$fx.txt'. For every other pattern the explicit '*' is identical to
  -- what addstar() would have appended.
  local pattern = vim.fn.escape(root .. segment, '\\*?[]{}`$') .. '*'
  for _, match in ipairs(vim.fn.getcompletion(pattern, 'file')) do
    if #items >= limit then
      break
    end
    -- getcompletion() answers in terms of the pattern it was handed, so the
    -- token's own prefix goes back on in place of the resolved one.
    local tail = match:sub(#root + 1)
    -- A bare '.' is how dotfiles are asked for, and getcompletion() answers it
    -- with './' and '../' ahead of them: neither completes anything past what
    -- was typed. '..' typed on purpose still lists '../'.
    if segment ~= '.' or (tail ~= './' and tail ~= '../') then
      items[#items + 1] = {
        label = dir .. tail,
        kind = vim.endswith(match, '/') and Kind.Folder or Kind.File,
      }
    end
  end
  return items
end

---The 'complete' function source. See |complete-functions|.
---@param findstart 0|1
---@return integer|table
function M.completefunc(findstart)
  if findstart == 1 then
    -- -2, not -3: -3 leaves completion mode, taking the other sources with it.
    return M.start() or -2
  end

  local words = {}
  local start = M.start()
  for i, item in ipairs(start and M.items() or {}) do
    words[i] = {
      -- The label, never insertText: each source anchors at the run it replaces.
      word = item.label,
      kind = Kind[item.kind],
      preselect = i == 1 and 1 or nil,
      -- Where `word` replaces from, for `sources.trim_head()` once
      -- vim.lsp.completion has re-inserted the item at the keyword boundary.
      user_data = { zcmp_start = start },
    }
  end
  -- 'refresh' re-runs the source as the leading text changes; without it,
  -- matches are only ever filtered down.
  return { words = words, refresh = 'always' }
end

---@param opts? zcmp.PathOpts
function M.enable(opts)
  options = opts or {}
end

return M
