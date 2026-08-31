<h1 align="center">ZCmp.nvim</h1>
<div align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/zuqini/zcmp.nvim/tests.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=tests&labelColor=1e1b4b"> <img src="https://img.shields.io/github/issues/zuqini/zcmp.nvim?style=for-the-badge&logo=github&logoColor=white&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/last-commit/zuqini/zcmp.nvim?style=for-the-badge&logo=neovim&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/license/zuqini/zcmp.nvim?style=for-the-badge&logo=opensourceinitiative&logoColor=white&color=8b5cf6&labelColor=1e1b4b">
</div>

<p align="center">A completion engine's configuration, for the completion engine Neovim already ships.</p>

**[Why ZCmp?](#why-zcmp)** | **[What you get](#what-you-get)** | **[Quick start](#quick-start)** | **[Sources](#sources)** | **[LSP](#lsp)** | **[Snippets](#snippets)** | **[Keymaps](#keymaps)** | **[API](docs/api.md)** | **[Providers](docs/sources.md)** | **[Coming from blink.cmp](docs/migration.md)**

## Why ZCmp?

Neovim 0.12 completes on its own. It opens the menu as you type
(`'autocomplete'`), takes a Lua function as a source (`'complete'`),
fuzzy-matches, ranks and time-slices what the sources answer, draws the
documentation popup, and asks language servers through
`vim.lsp.completion`. What it does not ship is a configuration for any of
that — which is the part everyone actually installs a completion plugin for.

ZCmp is that layer and nothing more. There is no engine here: no matcher of
its own, no menu drawing, no scoring, no binary to build. What you get is one
blink.cmp-shaped table over the options and APIs that already do the work —
and a set of defaults that has been through the sharp edges so your config
does not have to.

| | Engine | Menu | Sources | Ships |
| --- | --- | --- | --- | --- |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | its own (Rust matcher) | its own | its own protocol | a binary, or `cargo` |
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | its own | its own | its own protocol | ~7k lines of Lua |
| [mini.completion](https://github.com/nvim-mini/mini.completion) | core's | core's, plus its own info/signature windows | the omnifunc, and a fallback | one module |
| **ZCmp** | **core's** | **core's** | **`'complete'` entries** | **configuration** |

## What you get

**Every source in one ranked menu.** `'complete'` takes core's buffer
scanners, function sources and the LSP omnifunc together, fuzzy-matches
across all of them and caps each one separately (`.^100`). Nothing in ZCmp
re-ranks afterwards, because there is no afterwards.

**Each source anchors where it wants.** A `'complete'` function source
chooses its own start column, so a path (`./al`) and a snippet trigger
(`<div`, `#!`) replace what they should — something `vim.fn.complete()`,
with one start column for the whole menu, cannot express.

**A path source**, which core has none of: it finds where a path token
begins in a line and hands the listing itself to `getcompletion()` — the
trailing `/`, hidden dotfiles, `~/` expansion and all. Relative tokens
resolve against the buffer's directory, not the cwd.

**LSP wired the way core wants it.** Both delivery paths at once, the trigger
characters widened so the second one fires, the omnifunc kept out of
`'complete'` until a server is actually attached — and, because switching
`vim.lsp.completion` on is what buys them, auto-imports, snippet expansion and
resolved documentation on accept. [Details below](#lsp).

**Snippets from whatever expands them.** Jumping tabstops and clearing a
placeholder go through two functions that default to `vim.snippet`, so a
server's snippet items and any snippet plugin on `vim.snippet` are integrated
with no adapter and nothing to configure. [Details below](#snippets).

**Keys that give themselves back.** Every mapping is buffer-local and every
`'fallback'` runs whatever the key is mapped to without ZCmp in the way — a
buffer-local mapping is captured once, when ZCmp attached, but a global one
is looked up fresh on every press. An autopair plugin's `<CR>` keeps working
because ZCmp finds it, not because ZCmp knows it exists. A list naming a
snippet or signature command, or containing a function, is mapped in Select
mode too — blink.cmp's rule — so `<Tab>` jumps out of a placeholder you are
sitting on.

**A kind column you can read.** Most colourschemes leave `PmenuKind` linked to
`Pmenu`, so it reads as part of the label. ZCmp colours it — and re-derives
the highlight after a `:colorscheme`. [Details below](#appearance).

**An answer when the menu comes back empty.** `:ZCmp status` says which
sources are serving this buffer and what `'complete'` came out as;
`:checkhealth zcmp` adds the version, whether the options are still the ones
it set, whether a flag this Neovim lacks is silently changing behaviour, and
whether a second completion engine is loaded alongside — the failure that
looks like every other failure.

**Nothing you cannot take back.** `:ZCmp disable` removes the mappings and
restores what they displaced, gives every buffer the `'complete'` and
`'autocomplete'` it had, restores the global options and the two highlight
groups, and switches `vim.lsp.completion` off — trigger characters restored
— for every client of a buffer it drove, whoever switched it on: ZCmp owns
that wiring in its buffers (see [LSP](#lsp)), and nothing reports whether a
client had it before.

**What it does not do:** command-line completion (that is `'wildoptions'`,
a different mechanism entirely), a signature window that follows you through
an argument list, ghost text, per-source scoring, or drawing anything. If
you want those, blink.cmp is a good plugin and this is the wrong one.

## Requirements

- Neovim 0.12.0+
- Optional: [zsnip.nvim](https://github.com/zuqini/zsnip.nvim), which the
  `snippets` provider points at by default. Nothing else needs it — see
  [Snippets](#snippets).
- The `path` source recognises `/`-separated paths only — no Windows `C:\`
  or `C:/` support.

## Installation

```lua
-- vim.pack
vim.pack.add({
  'https://github.com/zuqini/zcmp.nvim',
  'https://github.com/zuqini/zsnip.nvim',
})

-- lazy.nvim / zpack.nvim
{
  'zuqini/zcmp.nvim',
  dependencies = { 'zuqini/zsnip.nvim' },
  config = function()
    require('zcmp').setup()
  end,
}
```

`setup()` is the one call a config needs: nothing is wired up until it runs.

## Quick start

```lua
require('zcmp').setup({
  keymap = { preset = 'enter' },
  sources = { default = { 'lsp', 'path', 'snippets', 'buffer' } },
})
```

That is the whole of it. The menu now opens as you type, ranks paths, buffer
words, snippets and server items together, shows documentation for the
selected one, and `<CR>` accepts it.

## Sources

A source is an entry in `'complete'`. ZCmp ships four providers:

| id | What it is | Needs |
| --- | --- | --- |
| `lsp` | `vim.lsp.omnifunc()`, plus `vim.lsp.completion` autotrigger | a language server |
| `path` | Filesystem paths, anchored at the token under the cursor | nothing |
| `snippets` | A snippet source; `zsnip.complete` by default | that module, or another |
| `buffer` | Core's own scanners: this buffer, other windows, other buffers | nothing |

`sources.default` is both the list and the priority order — it becomes
`'complete'` in the order you write it.

```lua
require('zcmp').setup({
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = {
      markdown = { 'path', 'buffer' },            -- replaces the default list
      lua = { inherit_defaults = true, 'mine' },  -- adds to it
    },
    providers = {
      buffer = { max_items = 50 },
      -- Anything 'complete' understands is a provider:
      spell = { flags = { 'kspell' } },
    },
  },
})
```

That last one is worth dwelling on: the tags file, a dictionary, the spell
file, included files — everything `:help 'complete'` lists is a source here,
ranked in the same menu as the rest, without anyone writing a plugin for it.

A provider with a `module` is one you can write yourself — a module with a
`completefunc`, which is roughly twenty lines — and
`zcmp.add_source_provider()` registers one from another plugin's config
block, before or after `setup()`, in either order. See
[docs/sources.md](docs/sources.md).

## LSP

The `lsp` source is two things at once, because each covers what the other
misses:

- **`vim.lsp.omnifunc()`**, called directly as a function source rather than
  through `'omnifunc'` — a user's or another plugin's own function left in
  that option can no longer stand in for it — which merges server items into
  the same ranked menu as everything else, but asks once per completion
  cycle, so typing on through `vim.` narrows nothing;
- **`vim.lsp.completion`'s autotrigger**, which re-asks per trigger character
  but answers nothing for a plain keyword. It opens the menu on its own,
  undelayed: `completion.menu.auto_show = false` switches it off along with
  `'autocomplete'` (the menu then opens on `<C-space>` only).

ZCmp widens the server's declared `triggerCharacters` to every letter, which
is what makes the second one fire at all, and puts the declared list back when
the last buffer using that client lets go of it.

### `'autocompletedelay'` is held at 0, and there is no option to change it

`'autocompletedelay'` delays core's scan of `'complete'`. It does not delay
the autotrigger, which is not a `'complete'` source: that asks the server
25 ms after a trigger character, and the trigger list has just been widened to
every letter. With any non-zero delay the server therefore answers first, on
the opening keystroke of every word.

The menu it answers into is `complete()`'s, and that is a different kind of
completion session — `complete_info().mode` reads `eval` rather than
`keyword`. Core re-scans `'complete'` only in a `keyword` session, so once the
LSP owns the menu, no `'complete'` source is asked again for the rest of the
cycle: `refresh = 'always'` has no loop left to be called from, and
`'autocomplete'` and `'autocompletetimeout'` stop applying too. Every non-LSP
source — path, snippets, the buffer scanners — is then missing from the menu
until a deletion ends the cycle.

At 0 the scan is synchronous on the keystroke, ahead of that 25 ms floor, so
the sources are in the menu before the server's answer merges into it. What it
costs is the debounce, in buffers with no client to lose the race to;
`'autocompletetimeout'` is core's own bound on a slow source there, and
`completion.menu.auto_show = false` still stops the menu opening as you type.

Core still scans `'complete'` only once per cycle, at the keystroke that opens
the menu, so a source with nothing to offer for the first character and a match
by the third does not reappear on its own. For the server — the source where
that matters most, since it is also the one that answers nothing to a single
letter — the `lsp` provider's `retrigger` closes the gap; see below.

### `retrigger`: asking the server again while a menu is open

`vim.lsp.completion` will not do this by itself. Both of its entry points give
up on `pumvisible()`:

```lua
-- on_insert_char_pre:  if vim.fn.pumvisible() ~= 0 then return end
-- trigger():           if vim.fn.pumvisible() ~= 0 and not Context.isIncomplete then return end
```

The widened trigger list is consulted only *after* that first check, so
widening buys an **opening** keystroke, never a refreshing one. The mechanism
core intends for refreshing is `isIncomplete`, which is the server's decision:
a server that answers `isIncomplete = true` (lua_ls after a `.`) is re-asked on
every keystroke for free, and one that answers `false` (lua_ls on a plain
keyword) is asked once. While `'autocompletedelay'` was non-zero this went
unnoticed, because the menu kept collapsing to no matches and every collapse
let the trigger list matter again.

So with `retrigger` on — the default — ZCmp takes the menu down for the length
of one synchronous call, asks through `vim.lsp.completion.get()`, and puts the
same items straight back. The server's answer then merges into them, and is
ranked against them, through `trigger()`'s own `prev_matches` path. ZCmp builds
nothing and ranks nothing: what goes back is what was already on screen.

It does nothing unless it has to. It runs only while a `vim.fn.complete()`
session owns the menu — in core's own `keyword` session, `'complete'` is
re-scanned every keystroke already — and it stands down while an item is
selected, so `<C-n>` is never interrupted. Set `retrigger = false` to turn it
off, and the server is asked once per menu, as core has it.

Switching `vim.lsp.completion` on is also what buys the parts of LSP
completion that are not a list of words. On accept, core expands a snippet
item through `vim.snippet`, applies the item's `additionalTextEdits` — the
import statement at the top of the file — and runs any command it carries. On
selection it asks `completionItem/resolve` and fills the documentation popup
with the answer. None of that happens in a buffer nobody enabled it on, and
enabling it is not the default.

`vim.lsp.omnifunc()` joins `'complete'` only once a client answering
`textDocument/completion` is attached, and leaves when the last one detaches.
That is the provider's `available`, and it is why `'complete'` in a buffer
with no server contributes nothing.

```lua
sources = {
  providers = {
    lsp = {
      opts = {
        autotrigger = true,               -- vim.lsp.completion's own trigger
        extend_trigger_characters = true, -- widen the list to every letter
      },
    },
  },
},
```

Turn `extend_trigger_characters` off for a server that misbehaves under a
widened list; autotrigger then only fires on the characters it asked for.
`autotrigger = false` switches the second path off for this provider alone,
as `completion.menu.auto_show = false` does for the menu as a whole.
Both keys are zcmp's own, and `setup()` checks them like any other option:
an unknown key or a wrong type is reported.

Delete a `vim.lsp.completion.enable(...)` call your own `LspAttach` handler
makes — the one in `:h lsp-attach`'s example. ZCmp owns `vim.lsp.completion`
in every buffer it drives: it drops and re-enables every completion-capable
client whenever one is newly wired, because Neovim reads `triggerCharacters`
and installs autotrigger only on a buffer handle's first `enable()`. A
synchronous handler that ran first used to win that race and silently defeat
the widening; any `convert`/`cmp` opts on your own call are dropped either
way.

`get_lsp_capabilities(override?, include_nvim_defaults?)` exists so a
blink.cmp config moves over unedited. ZCmp completes through core, so it is
`vim.lsp.protocol.make_client_capabilities()` with `override` merged in — a
config that never calls it loses nothing. `include_nvim_defaults = false`,
blink's own second argument, skips that base and returns `override` alone.

One default that is doing more than it looks:
`completion.list.selection.auto_insert = false` writes `noinsert` into
`'completeopt'`, which `'autocomplete'` ignores but `vim.lsp.completion`'s own
`vim.fn.complete()` call honours. Without it the server's first item is
inserted as you type, `vim.` becomes `vim.F`, and the next keystroke appends
to that.

## Snippets

ZCmp does not expand snippets and does not need to: whatever puts the snippet
in the buffer expands it. What ZCmp drives is the *session* — jumping tabstops
and clearing a placeholder — through two functions, which default to core's:

```lua
snippets = {
  active = function(filter) return vim.snippet.active(filter) end,
  jump = function(direction) vim.snippet.jump(direction) end,
}
```

So anything that expands through `vim.snippet` is already integrated, with no
adapter, no companion plugin and nothing to configure:

- **A language server's snippet items.** `vim.lsp.completion` expands them
  with `vim.snippet.expand()` on accept — core's doing, and it happens
  because ZCmp switched `vim.lsp.completion` on. Accept a function from your
  language server and `<Tab>` walks its arguments.
- **Any snippet plugin that expands with `vim.snippet`.**

An engine with a session of its own — LuaSnip — is one line, the same line
it is in blink.cmp:

```lua
require('zcmp').setup({ snippets = { preset = 'luasnip' } })
```

The preset rewrites the defaults of `snippets.expand`, `snippets.active` and
`snippets.jump` to LuaSnip's, and points the `snippets` provider at a source
ZCmp ships for it ([below](#where-the-snippets-in-the-menu-come-from)). An
explicit field still wins, the way it wins over any other default. One honest
limitation: a language server's snippet items expand through `vim.snippet`
regardless — that is `vim.lsp.completion`'s doing, not ZCmp's — so the
preset's functions ask LuaSnip first and fall through, and `<Tab>` walks
either engine's session.

`snippets.expand` is how ZCmp's own snippet sources — and zsnip's — expand
what gets accepted, so overriding it plugs in an engine there is no preset
for. A preset ZCmp does not know is reported by `setup()` rather than
silently treated as the default one.

### Where the snippets in the menu come from

Expanding a snippet is one thing; *offering* snippets as completion candidates
is another, and core has no source for it. That is what the `snippets`
provider id is for, and it points at
[zsnip.nvim](https://github.com/zuqini/zsnip.nvim)'s `'complete'` source by
default:

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
`expand` so an accepted item goes through `snippets.expand` rather than
zsnip's own default. Everything else about snippets — how many are offered,
whether they carry documentation — is configured in [zsnip's own
`setup()`](https://github.com/zuqini/zsnip.nvim), where the rest of zsnip
is.

It is a default, not a dependency. The provider is a `module` like any other,
so any snippet plugin exposing `source()` or `completefunc()` takes its place
under the same id, and dropping `snippets` from `sources.default` leaves the
rest of the menu untouched. `opts` follow the module: naming the shipped
default's module brings the shipped default's `opts` back with it
(`module = 'zsnip.complete'` over the luasnip preset keeps the two
coordination keys above), and any other module gets only the `opts` you give
it. If the module is not installed the provider contributes nothing, every
other source still resolves, and `:ZCmp status` names it.

For the plugins people arrive with, ZCmp ships the module:

- **LuaSnip** — `snippets.preset = 'luasnip'` already pointed the provider at
  `zcmp.sources.snippets.luasnip`; there is nothing more to write. `opts`:
  `limit` (default 100), `documentation` (default true), `show_condition`
  (default true).
- **[nvim-snippets](https://github.com/garymjr/nvim-snippets)** — one
  provider line:

  ```lua
  require('zcmp').setup({
    sources = {
      providers = { snippets = { module = 'zcmp.sources.snippets.nvim_snippets' } },
    },
  })
  ```

  `opts`: `limit` (default 100), `documentation` (default true).

Both adapters' `limit` is checked the same way: one that is not a whole
number `>= 1` is reported once and the default used.

zsnip is the one ZCmp ships *pointed at* because it already speaks
`'complete'` — being a function source, it picks its own start column, so a
`<div` trigger replaces the whole run rather than the keyword at the end of
it. The shipped modules do the same for the other two.

## Keymaps

Four presets, the same four blink.cmp has, and the same per-key overrides:

```lua
require('zcmp').setup({
  keymap = {
    -- 'default' — <C-y> accepts, <C-n>/<C-p> select, <Tab> jumps a snippet
    -- 'super-tab' — <Tab> accepts
    -- 'enter' — <CR> accepts
    -- 'none' — map it all yourself
    preset = 'enter',
    ['<Tab>'] = { 'select_next', 'snippet_forward', 'show_on_keyword', 'fallback' },
    ['<S-Tab>'] = { 'select_prev', 'snippet_backward', 'fallback' },
    ['<CR>'] = { 'select_and_accept', 'fallback' },
    ['<BS>'] = { 'snippet_delete', 'fallback' },
    ['<C-j>'] = {},     -- map nothing to this key
    ['<C-e>'] = false,  -- same as {}
  },
})
```

Every preset but `none` also brings `<C-space>`, `<Up>`/`<Down>`,
`<C-n>`/`<C-p>`, `<C-e>` to close the menu, `<S-Tab>` to jump a tabstop back,
`<C-b>`/`<C-f>` for the documentation popup, `<C-k>` for signature help and
`<C-y>` to accept — and `<CR>` as `{ 'fallback' }`, ZCmp's own addition to
blink's presets: Enter does exactly what it did before, but through ZCmp's
feeder, which closes a menu that has nothing selected ahead of the key —
without it, the menu `vim.lsp.completion` rebuilds once a server answers
swallows the first Enter. Under `none`, add `['<CR>'] = { 'fallback' }` if
you see that.

Each entry is tried in order until one reports that it did something.
`'fallback'` is the escape hatch: it runs whatever the key is mapped to
without ZCmp in the way — a buffer-local mapping is captured once, when ZCmp
attached, but a global one (a plugin's) is looked up fresh on every press, so
one defined after ZCmp attached still runs; failing either, the built-in
behaviour of the key runs instead. That is how `<Tab>` still indents, `<CR>`
still opens a line, and an autopair plugin still pairs. It always answers, so
write it last: a command after it can never run, and zcmp says so.

An entry that names a snippet or signature command, or contains a function,
is mapped in Select mode as well as Insert — the same rule as blink.cmp, so a
`<Tab>` reaches the placeholder a snippet leaves you on. There `fallback`
follows Vim's own rule for the key: an `smap`'s rhs runs in Select mode; any
other mapping the key resolves to — a `vmap`, a `:map` — runs from Visual on
the same selection instead, with Select mode restored once it has run; and
with no mapping at all, the key types as text, which in Select mode replaces
the selection.

An entry may also be a function, which is handed the commands table
(`require('zcmp.api')` — the list in [docs/api.md](docs/api.md), not the
module's `setup`/`enable`/`reload`) and answers `true`/`false`/`nil` like a
named command — or a string, keys in `<Key>` notation fed as if typed
(remapped, same as blink's own function entries, unless it contains the key
itself, which is fed non-recursively); an empty string passes the key to the
next command, the same as `false`:

```lua
['<C-l>'] = {
  function(cmp)
    return cmp.is_documentation_visible() and cmp.hide_documentation()
  end,
  'fallback',
},
```

Every command is also a function on the module — `require('zcmp').select_next()`
— so nothing here is reachable only through a keymap. The full list is in
[docs/api.md](docs/api.md).

Two commands are ZCmp's own, and have no blink.cmp equivalent:
`show_on_keyword` (open the menu, but only when a keyword precedes the cursor,
so a `<Tab>` bound to it still indents) and `snippet_delete` (delete the
selected placeholder and keep typing in its place).

A `keymap.preset` that is not one of the four, a command written after
`'fallback'`, and one key spelled twice are all reported by `setup()` — a
keymap that is wrong in one of these ways reads as the plugin being broken,
not as the key silently doing nothing, and an unknown preset falls back to
`default`. A name that is not a command — or is one of the predicates, such
as `is_visible` — is reported by `setup()` the same way, and skipped when the
key is pressed.

## Appearance

Core draws the menu, and most colourschemes leave `PmenuKind` linked to
`Pmenu`, so the kind column reads as part of the label. ZCmp sets `PmenuKind`
and `PmenuKindSel` from `appearance.kind_hl` (ZCmp's own; `Special` by
default), keeping the menu's own background and the selected row's, and
re-derives both after a `:colorscheme` — including the one your config sets
after `setup()` has run.
`appearance.kind_hl = false` leaves the groups alone; `disable()` puts back
what was there.

`'completeitemalign'` is core's, and orders the three columns it has.

## Configuration

```lua
require('zcmp').setup({
  -- Which buffers zcmp drives. Runs with that buffer current, so a
  -- no-argument function reading vim.bo/vim.b (blink.cmp's own form) works
  -- unedited.
  enabled = function(bufnr) return vim.bo[bufnr].buftype == '' end,

  keymap = { preset = 'default' },

  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = {},        -- filetype -> provider ids; `inherit_defaults = true`
                              -- adds them to `default` instead of replacing it
    providers = {},           -- see Sources, above
  },

  completion = {
    menu = {
      auto_show = true,                   -- 'autocomplete', and the lsp provider's
                                          -- autotrigger: open as you type
    },
    documentation = { auto_show = true }, -- `popup` in 'completeopt'
    list = {
      max_items = nil,                    -- default cap for providers with none
      selection = {
        preselect = true,                 -- select the item a source marked
        auto_insert = false,              -- when on, inserts before accepting
      },
    },
  },

  fuzzy = { enabled = true },             -- `fuzzy` in 'completeopt' (ZCmp's own; blink has no switch for its matcher)

  snippets = {
    preset = 'default',                   -- or 'luasnip', which rewrites the
                                          -- three below and the source
    expand = function(body) vim.snippet.expand(body) end,
    active = function(filter) return vim.snippet.active(filter) end,
    jump = function(direction) vim.snippet.jump(direction) end,
  },

  signature = { enabled = false },        -- whether `show_signature` does anything
  appearance = { kind_hl = 'Special' },   -- colour for the menu's kind column
})
```

An unknown key, or a known one of the wrong type, is reported with
`vim.notify` and otherwise ignored — the rest of the config still applies. A
`max_item` that should have been `max_items` is a silent no-op that reads
exactly like the option not working, so it is named instead. A value of the
wrong type keeps its default rather than landing in the resolved config —
a table-shaped option handed a scalar and a scalar leaf handed the wrong type
are pruned on the same terms — and every list-shaped option (`sources.default`,
a `per_filetype` list, a provider's `flags`, a keymap entry's command list) is
checked element by element and compacted afterwards, so a wrong-typed element
is reported and dropped like any other wrong-typed value, and the rest keep
their order; a `nil` in the list (the `cond and 'x' or nil` idiom) is simply
absent, rather than a hole the defaults get merged into. `setup()` handed
anything but a table warns and falls back to the defaults.

`setup()` also writes `shortmess+=c`: with the menu opening on nearly every
keystroke, `match 1 of 9` in the message line is noise.

### One thing worth knowing about `preselect`

`'autocomplete'` forces `noselect` on, and `preselect` in `'completeopt'` is
what overrides it — for items a source *marked* as preselected. ZCmp's path
source marks its first item, and language servers mark theirs when they have
an opinion. Core's own buffer scanners mark nothing, so a buffer word is never
under the cursor until you select it.

If you want `<CR>` to take the first match whatever produced it, bind
`select_and_accept` rather than `accept` — the difference between the two is
exactly this case.

A menu `show()` opens — `<C-space>` in every preset — obeys the same rule,
however it opened: with nothing marked, `<CR>` opens a line and
`select_and_accept` takes the first item. With `auto_show = false`, having
`<C-space><CR>` take the first item means binding `select_and_accept` to
`<CR>`.

On Neovim 0.12.0 there is no `preselect` flag at all, so *nothing* is ever
selected while the menu opens by itself, and `select_and_accept` is the only
binding that accepts anything. `:checkhealth zcmp` says so.

A menu `vim.lsp.completion` rebuilds once a server answers obeys the same
rule, now that ZCmp writes `noselect` itself: that restart goes through
`vim.fn.complete()`, which does not force the flag the way `'autocomplete'`
does. In such a menu a `<CR>` with nothing selected opens a line through
`fallback`, which closes the menu first — Vim's own rule for `noinsert` would
otherwise end completion without a newline. That is why every preset but
`none` maps `<CR>` to `fallback`; under `none`, that Vim rule applies as
written until you add `['<CR>'] = { 'fallback' }`.

## Commands and diagnostics

| Command | What it does |
| --- | --- |
| `:ZCmp` or `:ZCmp status` | What is serving this buffer, and what `'complete'` came out as |
| `:ZCmp enable` / `:ZCmp disable` | Take over completion, or hand it back |
| `:ZCmp reload` | Re-read the source list in every buffer zcmp drives, and start a provider module that has arrived since |

`:checkhealth zcmp` answers the questions an empty menu raises: whether the
engine is enabled and its options are still the ones it set, whether this
buffer is one ZCmp drives, which sources answered for it and which could not
(a provider whose module is not installed says so by name), whether this
Neovim is missing a `'completeopt'` flag the config asked for, and whether
another completion engine is loaded alongside. It ends with a minimal config
and what to put in a bug report.

## Coming from blink.cmp

The config shape is deliberately blink's, so most of one moves over as-is:
`keymap.preset` and per-key command lists, `sources.default` /
`per_filetype` / `providers`, `completion.menu.auto_show`,
`completion.documentation.auto_show`, `completion.list.selection`,
`snippets`, and `get_lsp_capabilities()`. The API function names are blink's
too.

What has no equivalent, and what ZCmp does instead, is in
[docs/migration.md](docs/migration.md).

## License

MIT
