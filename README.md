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
`'fallback'` runs whatever the key was mapped to before ZCmp took it — an
autopair plugin's `<CR>` keeps working because ZCmp finds it, not because
ZCmp knows it exists. A list containing a snippet command is mapped in Select
mode too, so `<Tab>` jumps out of a placeholder you are sitting on.

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
groups, and switches `vim.lsp.completion` back off for every client ZCmp
switched it on for — trigger characters included.

**What it does not do:** command-line completion (that is `'wildoptions'`,
a different mechanism entirely), a signature window that follows you through
an argument list, ghost text, per-source scoring, or drawing anything. If
you want those, blink.cmp is a good plugin and this is the wrong one.

## Requirements

- Neovim 0.12.0+
- Optional: [zsnip.nvim](https://github.com/zuqini/zsnip.nvim), which the
  `snippets` provider points at by default. Nothing else needs it — see
  [Snippets](#snippets).

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
| `lsp` | The omnifunc, plus `vim.lsp.completion` autotrigger | a language server |
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
      buffer = { max_items = 50, opts = {} },
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

- the **`o` flag** in `'complete'` — the omnifunc — which merges server items
  into the same ranked menu as everything else, but asks once per completion
  cycle, so typing on through `vim.` narrows nothing;
- **`vim.lsp.completion`'s autotrigger**, which re-asks per trigger character
  but answers nothing for a plain keyword.

ZCmp widens the server's declared `triggerCharacters` to every letter, which
is what makes the second one fire at all, and puts the declared list back when
the last buffer using that client lets go of it.

Switching `vim.lsp.completion` on is also what buys the parts of LSP
completion that are not a list of words. On accept, core expands a snippet
item through `vim.snippet`, applies the item's `additionalTextEdits` — the
import statement at the top of the file — and runs any command it carries. On
selection it asks `completionItem/resolve` and fills the documentation popup
with the answer. None of that happens in a buffer nobody enabled it on, and
enabling it is not the default.

The omnifunc joins `'complete'` only once a client answering
`textDocument/completion` is attached, and leaves when the last one detaches.
That is the provider's `available`, and it is why `'complete'` in a buffer
with no server has no dead `o` in it.

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

`get_lsp_capabilities(override?)` exists so a blink.cmp config moves over
unedited. ZCmp completes through core, so it is
`vim.lsp.protocol.make_client_capabilities()` with `override` merged in — a
config that never calls it loses nothing.

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
  -- ZCmp owns 'complete', so zsnip is told not to append itself to it.
  opts = { complete = false },
},
```

That one key is the whole of the coordination. Everything else about
snippets — how many are offered, whether they carry documentation — is
configured in [zsnip's own `setup()`](https://github.com/zuqini/zsnip.nvim),
where the rest of zsnip is.

It is a default, not a dependency. The provider is a `module` like any other,
so any snippet plugin exposing `source()` or `completefunc()` takes its place
under the same id, and dropping `snippets` from `sources.default` leaves the
rest of the menu untouched. If the module is not installed the provider
contributes nothing, every other source still resolves, and `:ZCmp status`
names it.

For the plugins people arrive with, ZCmp ships the module:

- **LuaSnip** — `snippets.preset = 'luasnip'` already pointed the provider at
  `zcmp.sources.snippets.luasnip`; there is nothing more to write.
- **[nvim-snippets](https://github.com/garymjr/nvim-snippets)** — one
  provider line:

  ```lua
  require('zcmp').setup({
    sources = {
      providers = { snippets = { module = 'zcmp.sources.snippets.nvim_snippets' } },
    },
  })
  ```

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
    ['<C-e>'] = { 'hide', 'fallback' },
    ['<CR>'] = { 'select_and_accept', 'fallback' },
    ['<BS>'] = { 'snippet_delete', 'fallback' },
    ['<C-j>'] = {},  -- map nothing to this key
  },
})
```

Every preset but `none` also brings `<C-space>`, `<Up>`/`<Down>`,
`<C-n>`/`<C-p>`, `<S-Tab>` to jump a tabstop back, `<C-b>`/`<C-f>` for the
documentation popup, `<C-k>` for signature help and `<C-y>` to accept.

Each entry is tried in order until one reports that it did something.
`'fallback'` is the escape hatch: it runs whatever the key was mapped to
before ZCmp attached — a buffer-local mapping, a plugin's global one, or the
built-in behaviour of the key. That is how `<Tab>` still indents, `<CR>` still
opens a line, and an autopair plugin still pairs. It always answers, so write
it last: a command after it can never run, and zcmp says so.

An entry may also be a function, which is handed the commands table
(`require('zcmp.api')` — the list in [docs/api.md](docs/api.md), not the
module's `setup`/`enable`/`reload`):

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

A name that is not a command, and a command written after `'fallback'`, are
both reported with `vim.notify` — a key that quietly does nothing reads as the
plugin being broken.

## Appearance

Core draws the menu, and most colourschemes leave `PmenuKind` linked to
`Pmenu`, so the kind column reads as part of the label. ZCmp sets `PmenuKind`
and `PmenuKindSel` from `appearance.kind_hl` (`Special` by default), keeping
the menu's own background and the selected row's, and re-derives both after a
`:colorscheme` — including the one your config sets after `setup()` has run.
`appearance.kind_hl = false` leaves the groups alone; `disable()` puts back
what was there.

`'completeitemalign'` is core's, and orders the three columns it has.

## Configuration

```lua
require('zcmp').setup({
  -- Which buffers zcmp drives.
  enabled = function(bufnr) return vim.bo[bufnr].buftype == '' end,

  keymap = { preset = 'default' },

  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = {},        -- filetype -> provider ids; `inherit_defaults = true`
                              -- adds them to `default` instead of replacing it
    providers = {},           -- see Sources, above
  },

  completion = {
    menu = { auto_show = true },          -- 'autocomplete': open as you type
    documentation = { auto_show = true }, -- `popup` in 'completeopt'
    list = {
      max_items = nil,                    -- default cap for providers with none
      selection = {
        preselect = true,                 -- select the item a source marked
        auto_insert = false,              -- when on, inserts before accepting
      },
    },
    trigger = { delay_ms = 200 },         -- 'autocompletedelay'
  },

  fuzzy = { enabled = true },             -- `fuzzy` in 'completeopt'

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
exactly like the option not working, so it is named instead.

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

On Neovim 0.12.0 there is no `preselect` flag at all, so *nothing* is ever
selected while the menu opens by itself, and `select_and_accept` is the only
binding that accepts anything. `:checkhealth zcmp` says so.

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
