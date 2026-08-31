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

- **`flags`** (zcmp's own — blink.cmp providers have no such field) are
  written into `'complete'` as they stand, so anything the
  option understands is a provider: `kspell` for the spell file, `t` for tags,
  `k/usr/share/dict/words` for a dictionary, `i` for included files. See
  `:help 'complete'`. Compacted like every other list-shaped option: a
  `cond and 'w' or nil` element that evaluates to `nil` is simply absent
  (`{ '.', want and 'w' or nil, 'b' }` leaves `flags = { '.', 'b' }` when
  `want` is false), rather than a hole the default list gets merged into.
- **`enabled`** and **`available`** (zcmp's own — blink.cmp's `enabled` takes
  the same shape, but it has nothing named `available`) are both asked per
  buffer, on every resolve, in that order: `available` runs only once
  `enabled` has answered true. They differ in one place — the wiring
  ZCmp uses to decide whether to switch `vim.lsp.completion` on for
  the `lsp` provider honours `enabled` but never asks `available`, so a
  server not yet attached is kept out of `'complete'` by `available` alone.
  Both run with the buffer being decided set current, not whichever buffer
  happens to be on screen when the resolve runs — so a no-argument function
  reading `vim.bo`/`vim.b` (blink.cmp's own form for `enabled`) works
  unedited.
- **`max_items`** becomes `^{count}` on every entry the provider contributes,
  which is core's own per-source cap. `completion.list.max_items` is the
  default for providers that set none. An entry that already carries its own
  count — a `flags` entry written as `.^50`, or a `source()` answer with a
  `^` in it — keeps that count instead, and `max_items` is skipped for it,
  with a warning once: appending a second `^{count}` produces `^50^100`,
  which `'complete'` refuses with E535 and detaches the whole buffer.
  An empty `flags` entry is dropped rather than written, and named in
  `:ZCmp status` / `:checkhealth zcmp`; a `module`'s `source()` answering
  `''`, `nil`, something other than a string, or raising is reported there
  the same way, with the provider's `flags` still written.

The `path` provider recognises `/`-separated paths only — no Windows `C:\`
or `C:/` support.

## Writing a provider module

A module is a source if it has either of:

- **`source(opts)` → `string`** — the `'complete'` entry to use, for a module
  that knows its own (zsnip's `zsnip.complete.source()` is one).
- **`completefunc(findstart, base)`** — a `'complete'` function, in which case
  ZCmp writes the entry itself.

If a module has both, `source()` takes precedence and `completefunc()` is
never called: `source()`'s answer *is* the entry, including when it answers
`nil` -- which is reported the same as any other answer that is not a
non-empty string, not treated as "no `source()` at all".

If the module also has **`enable(opts)`**, it is called once, with the
provider's `opts`, the first time the provider joins a buffer's source list —
and again after every `setup()`, `add_source_provider()` and
`add_filetype_source()`, each of which re-resolves the options so that every
module starts again with the `opts` that came out, and after `zcmp.reload()`. `source()` must not depend on it: `:ZCmp status` and
`:checkhealth zcmp` ask a provider for its entry without starting anything, so
they can reach `source()` before any `enable()` has run.

`zcmp.reload()` is how you ask a module that would not start to try again. A
module whose chunk never loaded — a syntax error, `require()` finding
nothing, or a chunk that returned something other than a table — is re-read:
the next `reload()`/`setup()` re-reads the file, no `package.loaded` surgery
needed. Only a module whose chunk loaded but whose `enable()` raised keeps
its cached chunk: `reload()` re-runs that cached `enable()` rather than
re-reading the file — it recovers a transient cause, such as a dependency
that arrives after zcmp does, not a fix to the module's own source. A fix to
*that* file needs `package.loaded['my.source'] = nil` before the next
`reload()`/`setup()`, or a Neovim restart. The same goes for a *dependency*
of the module whose chunk raised: `reload()` drops only the module's own
cache entry, so the dependency keeps `require()`'s sentinel — the error
reads `loop or previous error loading module '<dep>'` — until
`package.loaded['<dep>'] = nil`.

A module is a singleton: started once, by the first provider that names it.
Two providers pointing at one module get one `enable(opts)`: whichever comes
first in the source-list order of the buffer that resolves it first.
`enable()` must therefore be idempotent — it runs again on
every `setup()`, `:ZCmp reload`, `:ZCmp enable` after a `:ZCmp disable`, and
registration, by any plugin — and it has no inverse: `zcmp.disable()` gives
back everything ZCmp itself wrote, not whatever the module set up on its own.

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
  -- covers what the other misses. `completion.menu.auto_show = false` turns
  -- this off too -- the menu then opens on <C-space> only -- and
  -- `auto_show_delay_ms` does not delay it.
  autotrigger = true,
  -- Widen the server's declared triggerCharacters to every letter, which is
  -- what makes autotrigger fire on a plain keyword at all. Turn it off for a
  -- server that misbehaves under a widened list; autotrigger then only fires
  -- on the characters the server asked for.
  extend_trigger_characters = true,
},

path = {
  limit = 250, -- entries listed per request
},
```

The two `lsp` keys are zcmp's own, and `setup()` checks them like any other
option: an unknown key or a wrong type is reported. So are `path`'s `limit`
and the shipped snippet adapters' keys (`limit`, `documentation`,
`show_condition` -- see below), once the provider reaches one of them. The
check follows the module, not the id -- the `module` set in `setup()`, else a
registration's, else the shipped default with `snippets.preset` applied -- so
a `lsp` provider whose `module` points elsewhere keeps its `opts` opaque, and
the default snippets provider's `opts` are zsnip's to check.

`path`'s cap is its own `opts.limit` rather than `max_items` at the provider
level, because truncating before the items are built is strictly less work
than `'complete'`'s `^{count}` truncating after. An `opts.limit` that is not
a whole number `>= 1` is reported once and handled the same as a bad
`max_items`: a fraction is rounded down, anything else falls back to the
default.

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
  opts = {
    -- ZCmp owns 'complete', so zsnip is told not to append itself to it.
    complete = false,
    -- Route an accepted zsnip item through `snippets.expand`, so a preset
    -- -- LuaSnip, say -- or an override set later still applies.
    expand = function(body)
      require('zcmp.config').options.snippets.expand(body)
    end,
  },
},
```

Both keys are coordination, not preference. `complete` because ZCmp is the
single writer of `'complete'`, so zsnip must not append itself to it;
`expand` so an accepted item goes through `snippets.expand` and the active
preset rather than zsnip's own default. How many snippets are offered and
whether they carry documentation is zsnip's own `setup()` to decide; anything
else put in `opts` here is handed to zsnip verbatim and overrides that
`setup()` for this source alone.

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
untouched. `opts` follow the module: naming the shipped default's module
brings the shipped default's `opts` back with it (`module = 'zsnip.complete'`
over the luasnip preset keeps the two coordination keys above), and any other
module gets only the `opts` you give it.

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
(a `refresh = 'always'` source narrows for itself), answering nothing on an
empty run while `'autocomplete'` is on -- as zsnip does, or the whole list
would open after every space typed; a manual `<C-n>` still lists it -- and
replacing the inserted trigger with the expansion on `CompleteDone`. An
adapter for another
snippet plugin is an enumeration loop away — read either shipped one. Both
adapters' `limit` is checked there, too, and the check is part of the module
contract: a module that takes `opts.limit` can validate it with
`require('zcmp.sources').limit(opts, default, name)`, which returns the value,
or `default` after reporting once, on the same terms as `max_items` — a
fraction rounds down, anything else falls back. `name` is how the report names
the module: pass the module's own dotted name, as both shipped sources do
(`zcmp.sources.path`, `zcmp.sources.snippets.luasnip`). A short leaf label
reads better but collides — `vim.notify_once` keys on the message text, so two
modules reporting under one label silence each other, and the surviving warning
names the wrong one.

The other part of the contract is one datum, optional, for a module whose
start column is not the keyword boundary -- as both shipped snippet
adapters' and `path`'s are not: it records the absolute (0-based) column
each item's `word` was built against as `user_data.zcmp_start` on the item.
With a client attached, `vim.lsp.completion`'s `trigger()` rebuilds the menu
through `vim.fn.complete()` at *one* column, the server's start or the
`\k*$` keyword boundary, and carries every item already on screen across as
it is. An item whose `findstart` answered somewhere else is then re-inserted
after its own head: `console.log` typed as `console.l` comes out as
`console.console.log`, `./sub/alpha.txt` after `./sub/al` as
`./sub/./sub/alpha.txt`. Since the restart is ZCmp's doing, undoing it is
too: a `CompleteDone` handler of ZCmp's own -- one of the autocmds `disable()`
removes -- removes whatever core left between the item's start and where the
word actually landed (`require('zcmp.sources').trim_head(item)`). It is a
no-op when nothing was relocated, or when the word is not at the cursor at
all. A module that does nothing at `CompleteDone` need only record the key,
or nothing for an exactly typed head. A module whose *own* `CompleteDone`
handler reads the completed word's position calls `trim_head(item)` first,
as the shipped snippet core does: the two handlers are in different augroups,
so which fires first is nothing to rely on, and the trim is idempotent, so
it does not matter which ran before it.

A module that records nothing -- the default provider, zsnip, or any other
plugin's function source -- is still put back when the text before the word
ends with the word's own head, typed exactly: `console.` ahead of
`console.log`, `x<` ahead of `x<div`. The head has to contain a non-keyword
character, which a head the restart skipped always does and a buffer word never
has, so a word accepted after itself is left as two. Reading the head off the
text cannot tell that relocation apart from an F source whose own `findstart`
simply happens to sit behind a matching byte, so this rule only applies where
`vim.lsp.completion`'s restart can actually have run. Any one of three things
means it could: the buffer's `lsp` provider has wired a client's autotrigger;
its omnifunc entry sits in 'complete' with a completion-capable client attached
-- `vim.lsp.omnifunc` reaches the restart on its own, whether or not zcmp wired
anything, so a source list naming the `lsp` provider under any id still counts;
or 'complete' carries a plain `o` flag while 'omnifunc' is Neovim's own
`v:lua.vim.lsp.omnifunc`, which core sets itself when a completion-capable
client attaches to a buffer whose 'omnifunc' is still empty. That last is the
same restart under a name zcmp does not spell, and it is how a config written
against the `o` flag -- zcmp's own spelling of this source until 2026-08-26 --
still reaches it. An `o` over somebody else's 'omnifunc' has no route there and
does not count, nor does a client attached for hover or diagnostics alone. With
none of the three, nothing is trimmed. The server's own items are placed by the
restart itself, never relocated, and left alone whatever their word holds --
`print(...)` accepted inside a typed `print(` stays nested. Recording
`zcmp_start` is what makes a fuzzily typed head exact too: `cnsl.l` accepted as
`console.log` is put back only from the recorded column.

If a provider's module is missing — zsnip not installed, say — the provider
contributes nothing and every other source still resolves. `:ZCmp status` and
`:checkhealth zcmp` name it.

A snippet source is the clearest case for [where each source
starts](#where-each-source-starts): as a `'complete'` function source it picks
its own start column, so a `<div` trigger replaces the whole run rather than
the keyword at the end of it.
