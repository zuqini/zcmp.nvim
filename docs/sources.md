# Sources and providers

A source in ZCmp is an entry in `'complete'`. That is the whole abstraction:
there is no provider protocol of ZCmp's own, no async contract, no scoring
callback. Core collects the sources, fuzzy-matches across all of them, ranks
the result and time-slices the slow ones.

## The provider table

```lua
require('zcmp').setup({
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    providers = {
      example = {
        name = 'Example',     -- shown by :ZCmp status and :checkhealth zcmp
        flags = { '.', 'w' }, -- literal 'complete' flags
        module = 'my.source', -- a module serving matches; see below
        opts = {},            -- passed verbatim to the module
        max_items = 100,      -- applied as 'complete's own ^{count} cap
        enabled = true,       -- boolean, or fun(bufnr): boolean
        available = function(bufnr) return true end,
      },
    },
  },
})
```

A provider needs `flags`, `module`, or both. Everything else is optional.

- **`flags`** are written into `'complete'` as they stand, so anything the
  option understands is a provider: `kspell` for the spell file, `t` for tags,
  `k/usr/share/dict/words` for a dictionary, `i` for included files. See
  `:help 'complete'`.
- **`enabled`** is asked once per resolve; **`available`** is asked per buffer,
  after it. The built-in `lsp` provider uses `available` to keep the omnifunc
  out of `'complete'` until a server that answers completion is attached.
- **`max_items`** becomes `^{count}` on every entry the provider contributes,
  which is core's own per-source cap. `completion.list.max_items` is the
  default for providers that set none.

## Writing a provider module

A module is a source if it has either of:

- **`source(opts)` → `string`** — the `'complete'` entry to use, for a module
  that knows its own (zsnip's `zsnip.complete.source()` is one).
- **`completefunc(findstart, base)`** — a `'complete'` function, in which case
  ZCmp writes the entry itself.

If the module also has **`enable(opts)`**, it is called once, with the
provider's `opts`, the first time the provider joins a buffer's source list —
and again after a later `setup()` or `zcmp.reload()`, which offer it the `opts`
they resolved. `source()` must not depend on it: `:ZCmp status` and
`:checkhealth zcmp` ask a provider for its entry without starting anything, so
they can reach `source()` before any `enable()` has run.

That is the entire contract. A working source, in full:

```lua
-- lua/my/source.lua
local M = {}

local WORDS = { 'alpha', 'beta', 'gamma' }

---@param findstart 0|1
---@return integer|table
function M.completefunc(findstart)
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = vim.api.nvim_get_current_line():sub(1, col)

  if findstart == 1 then
    -- Where the text this source replaces begins. -2 keeps completion mode
    -- alive with nothing to offer; -3 would leave it, taking the other
    -- sources with it.
    local start = before:match('()%w*$')
    return start and start - 1 or -2
  end

  local words = {}
  for _, word in ipairs(WORDS) do
    words[#words + 1] = { word = word, kind = 'Text' }
  end
  -- Without 'always', Vim narrows the list it was handed by prefix as you
  -- type, rather than asking again.
  return { words = words, refresh = 'always' }
end

return M
```

```lua
require('zcmp').setup({
  sources = {
    default = { 'lsp', 'mine', 'buffer' },
    providers = { mine = { name = 'Mine', module = 'my.source', max_items = 20 } },
  },
})
```

`:help complete-functions` is the reference for what `completefunc` may
return, and `:help complete-items` for the shape of each match.

### Two things that are easy to get wrong

- **Answer from the live line, not from `base`.** `base` is the text located
  in the *first* call of a completion cycle. On a `refresh = 'always'`
  re-invocation it is not re-derived, so it goes stale the moment you type.
  Read the cursor and the line instead.
- **Mark the first item `preselect = 1`** if you want it under the cursor.
  `'autocomplete'` forces `noselect` on, and `preselect` in `'completeopt'`
  only selects items a source asked for.

## Where each source starts

The reason `'complete'` matters more than it looks: a function source picks
its own start column, and different sources in the same menu may pick
different ones. A path source anchors at `./al`, a snippet source at the whole
`<div` run, and core's scanners at the keyword — all in one menu, all
replacing the right thing on accept.

`vim.fn.complete()`, which every completion plugin built before 0.12 has to
use, takes one start column for the entire menu. That is the constraint this
plugin exists to be free of.

## Per-filetype lists

```lua
require('zcmp').setup({
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = {
      -- Replaces the default list for markdown:
      markdown = { 'path', 'buffer', 'spell' },
      -- Adds to it for lua:
      lua = { inherit_defaults = true, 'lazydev' },
    },
  },
})
```

`zcmp.add_filetype_source(filetype, ids)` does the second form from Lua.

## The built-in providers' `opts`

The `lsp` and `path` providers take `opts` of their own:

```lua
lsp = {
  -- Ask the server again on every trigger character, through
  -- vim.lsp.completion. Both delivery paths are on by default because each
  -- covers what the other misses.
  autotrigger = true,
  -- Widen the server's declared triggerCharacters to every letter, which is
  -- what makes autotrigger fire on a plain keyword at all. Turn it off for a
  -- server that misbehaves under a widened list; autotrigger then only fires
  -- on the characters the server asked for.
  extend_trigger_characters = true,
},

path = {
  max_items = 250, -- entries listed per request
},
```

`path`'s cap is its own rather than `max_items` at the provider level, because
truncating before the items are built is strictly less work than `'complete'`'s
`^{count}` truncating after.

## Snippets

Two separate things wear this name, and only one of them is a source.

**Expanding and jumping** is not ZCmp's, and needs no provider: whatever puts
the snippet in the buffer expands it, and `snippets.active` / `snippets.jump`
drive the session afterwards. Both default to `vim.snippet`, so a language
server's snippet items — which `vim.lsp.completion` expands through
`vim.snippet.expand()` — work with nothing configured at all. See
[the README](../README.md#snippets).

**Offering snippets as candidates** is a source, and core has none. That is
what the `snippets` provider id is for. It points at
[zsnip.nvim](https://github.com/zuqini/zsnip.nvim)'s own `'complete'` source
by default:

```lua
snippets = {
  name = 'Snippets',
  module = 'zsnip.complete',
  -- ZCmp owns 'complete', so zsnip is told not to append itself to it.
  opts = { complete = false },
},
```

That one key is the whole of the coordination, and it is the only opinion
these `opts` hold. How many snippets are offered and whether they carry
documentation is zsnip's own `setup()` to decide; anything else put in `opts`
here is handed to zsnip verbatim and overrides that `setup()` for this source
alone.

Nothing else is needed — register a loader and the snippets are in the menu:

```lua
require('zsnip').setup()
require('zsnip.loaders.from_vscode').lazy_load()
require('zsnip.loaders.from_snipmate').lazy_load()
require('zcmp').setup()
```

Do not also call `require('zsnip.complete').enable()` or
`require('zsnip').start_lsp_server()`: either one offers every snippet a
second time. `:checkhealth zsnip` says so if you do.

That is a default, not a dependency. The provider is a `module` like any
other, so a snippet plugin exposing `source()` or `completefunc()` takes its
place under the same id:

```lua
sources = { providers = { snippets = { module = 'my.snippet.source' } } },
```

and dropping `snippets` from `sources.default` leaves the rest of the menu
untouched.

For the plugins people arrive with, the module is already written:

- **LuaSnip** — `snippets.preset = 'luasnip'` points the provider at
  `zcmp.sources.snippets.luasnip` by itself (and swaps the session functions;
  see [the README](../README.md#snippets)). An accepted match expands by
  reference through `luasnip.snip_expand()`. Regex-trigger and hidden
  snippets are not offered, and each snippet's `show_condition` is honoured.
  `opts`: `limit` (default 100), `documentation` (default true),
  `show_condition` (default true).
- **nvim-snippets** — one provider line:

  ```lua
  sources = {
    providers = { snippets = { module = 'zcmp.sources.snippets.nvim_snippets' } },
  },
  ```

  Bodies are LSP snippet text, expanded through `snippets.expand` —
  `vim.snippet` by default, exactly what nvim-snippets expects. `opts`:
  `limit` (default 100), `documentation` (default true).

Both are built on `zcmp.sources.snippets`, which owns what every snippet
source must get right: the start column, fuzzy-matching its own list
(a `refresh = 'always'` source narrows for itself), and replacing the
inserted trigger with the expansion on `CompleteDone`. An adapter for another
snippet plugin is an enumeration loop away — read either shipped one.

If a provider's module is missing — zsnip not installed, say — the provider
contributes nothing and every other source still resolves. `:ZCmp status` and
`:checkhealth zcmp` name it.

A snippet source is the clearest case for [where each source
starts](#where-each-source-starts): as a `'complete'` function source it picks
its own start column, so a `<div` trigger replaces the whole run rather than
the keyword at the end of it.
