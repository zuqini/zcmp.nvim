# ZCmp.nvim API

Everything on `require('zcmp')`. The command functions are also what a
[keymap](#commands) entry names by string, so a key list and a Lua call reach
the same code.

## Setup

### `zcmp.setup(opts?)`

Merges `opts` over the defaults, creates `:ZCmp`, and enables the engine.
Nothing is wired up until it runs. See the [configuration
reference](../README.md#configuration) for every option.

```lua
require('zcmp').setup({ keymap = { preset = 'enter' } })
```

An unknown key, or a known one of the wrong type, is reported with
`vim.notify` and otherwise ignored. A table-shaped option handed a scalar,
or a scalar leaf handed the wrong type, keeps its default rather than
landing in the resolved config, so a config that is wrong in one place still
gets the rest; every list-shaped option (`sources.default`, a `per_filetype`
list, a provider's `flags`, a keymap entry's command list) is checked element
by element and compacted afterwards, so a wrong-typed element is reported and
dropped like any other wrong-typed value, and the rest keep their order; a
`nil` in the list (the `cond and 'x' or nil` idiom) is simply absent, rather
than a hole the defaults get merged into. A `keymap.preset` that is not one
of the four is reported the same way, and falls back to `default`; so are a
command written after `fallback` in a keymap entry, one key spelled twice,
and a name that is not a command (or is a predicate such as `is_visible`).
`setup()` handed anything but a table warns and falls
back to the defaults.

### `zcmp.enable()`

Take over completion: write the options, install the autocmds, and attach to
every buffer already open. `setup()` calls it; call it yourself only after
`disable()`. Also re-runs every provider module's `enable(opts)`, same as
`setup()` and `zcmp.reload()`. Below Neovim 0.12.0 it reports that and wires
nothing, rather than failing on the first option this Neovim does not have.

### `zcmp.disable()`

Hand completion back. Mappings are removed and whatever they displaced is put
back, buffers get the `'complete'` and `'autocomplete'` they had before, the
global options ZCmp wrote and the two `PmenuKind*` highlight groups are
restored, trigger characters are put back as the server declared them, and
`vim.lsp.completion` is switched off for every client of a buffer ZCmp drove
— whoever switched it on. ZCmp owns that wiring in its buffers, and nothing
reports whether a client had it before; a config that enabled it itself is
one that should not have (see [LSP](../README.md#lsp)).

### `zcmp.is_enabled()` → `boolean`

Whether `enable()` has run and `disable()` has not — the engine switch, for
every buffer alike. Not blink.cmp's `is_enabled()`, which evaluates the
`enabled` predicate for the current buffer; `:ZCmp status` reports that (as
"attached"/"not attached") for the current one.

### `zcmp.reload()`

Re-derive `'complete'` in every buffer zcmp drives, and start any provider
module that has arrived since. What `:ZCmp reload` runs. Does nothing while
disabled.

### `zcmp.version` → `string`

## Sources

### `zcmp.add_source_provider(id, provider)`

Register a provider. It serves nothing until a `sources.default` or
`sources.per_filetype` list names it.

```lua
require('zcmp').add_source_provider('spell', { name = 'Spell', flags = { 'kspell' } })
```

Every `setup()`, `add_source_provider()` and `add_filetype_source()`
re-resolves the options, and every provider module's `enable()` runs again
with the re-resolved `opts` on the next pass — so a re-registered id reaches
its module's `enable()` with the new `opts`, and so does every other module.

See [docs/sources.md](sources.md) for the provider table in full.

### `zcmp.add_filetype_source(filetype, ids)`

Add one or more providers to a filetype's list, on top of `sources.default`.

```lua
require('zcmp').add_filetype_source('markdown', 'spell')
```

Both are order-free: a call before `setup()` survives it (`setup()` replaces
the resolved options, and registrations go underneath, so an explicit `opts`
still wins), and a call after it re-derives `'complete'` in every attached
buffer.

### `zcmp.get_lsp_capabilities(override?, include_nvim_defaults?)` → `lsp.ClientCapabilities`

Capabilities to hand a language server. ZCmp completes through core, so these
are `vim.lsp.protocol.make_client_capabilities()` with `override` merged in —
there is nothing of ZCmp's own to announce, and a config that does not call
this loses nothing. `include_nvim_defaults = false`, blink.cmp's own second
argument, skips that base and returns `override` alone.

## Commands

Each returns whether it did anything. That is what lets a keymap entry fall
through: `{ 'select_next', 'snippet_forward', 'fallback' }` tries each in turn
until one answers `true`.

`fallback` always answers, so it ends the list: anything written after it can
never run, and zcmp says so with `vim.notify`. Write it last.

An entry that names a snippet or signature command, or contains a function, is
mapped in Select mode as well as Insert — the same rule as blink.cmp, so it
reaches the placeholder a snippet leaves you on.

The predicates in the tables below (`is_visible`/`is_menu_visible`,
`is_snippet_active`, `is_documentation_visible`, `is_signature_visible`) are
callable the same way, including on the `cmp` a function entry receives, but
cannot be named in a keymap list — each answers a question rather than doing
anything, and naming one declines the same way a typo does.

### The menu

| Function | Does | Answers false when |
| --- | --- | --- |
| `show()` | Opens the menu, with nothing selected unless a source marked an item — the same rule as a menu that opened by itself | it is already open, or you are not in Insert mode |
| `show_on_keyword()` | `show()`, but only with a keyword before the cursor | there is none — so a `<Tab>` bound to it still indents |
| `hide()` / `cancel()` | Closes it, restoring the text as typed | it is not open |
| `select_next()` / `select_prev()` | Moves through it | it is not open |
| `accept(opts?)` | Accepts the selected item | nothing is selected |
| `select_and_accept(opts?)` | Accepts the selected item, or the first one | the menu is not open |
| `is_visible()` / `is_menu_visible()` | — | — |

`opts.callback` is called once the item has landed (on `CompleteDone`). If a
command earlier in the same list already closed the menu — `{ 'hide',
function(cmp) return cmp.accept({ callback = f }) end }`, where `hide()`'s
`<C-e>` ends completion before `accept()`'s own `<C-y>` can — nothing landed,
and `f` is never called:

```lua
['<CR>'] = {
  function(cmp)
    return cmp.accept({ callback = function() vim.cmd('startinsert!') end })
  end,
  'fallback',
},
```

`accept` and `select_and_accept` differ only when nothing is selected, which
with `'autocomplete'` is the common case for sources that mark no preselect —
see [the note in the README](../README.md#one-thing-worth-knowing-about-preselect).
A menu `show()` opens obeys the same rule, so with nothing marked
`<C-space><CR>` opens a line under every preset but `none`; with `auto_show =
false` — which also switches the `lsp` provider's autotrigger off, so the menu
opens on `<C-space>` only — bind `select_and_accept` to have `<CR>` take the
first item. The menu `vim.lsp.completion` rebuilds once a server answers obeys
the same rule, since ZCmp writes `noselect` itself; a `<CR>` with nothing
selected in such a menu opens a line through `fallback`, which closes the menu
first — Vim's own rule for `noinsert` would otherwise end completion without a
newline. That is why `<CR>` is `{ 'fallback' }` in every preset but `none`,
ZCmp's own addition to blink's presets; under `none`, add it yourself.

### Snippets

| Function | Does | Answers false when |
| --- | --- | --- |
| `snippet_forward()` / `snippet_backward()` | Jumps a tabstop | there is none in that direction |
| `snippet_delete()` | Deletes the selected placeholder, leaving you in Insert | no placeholder is selected |
| `is_snippet_active(filter?)` / `snippet_active(filter?)` | — | — |

All of them go through `config.snippets`, so an engine other than
`vim.snippet` is a preset away — `snippets.preset = 'luasnip'` — or, for one
there is no preset for, the `snippets.expand`, `snippets.active` and
`snippets.jump` functions written out. Because the default is `vim.snippet`,
a server's snippet items and any snippet plugin that expands through it are
already integrated — see [the README](../README.md#snippets).

`snippets.expand` is called for what ZCmp's own snippet sources — and
zsnip's — put in the buffer. A server's snippet items are expanded by
`vim.lsp.completion` through `vim.snippet` regardless, which is why the
`'luasnip'` preset's `active` and `jump` ask LuaSnip first and fall through.
A preset ZCmp does not know is reported by `setup()` rather than ignored.

### Documentation

| Function | Does | Answers false when |
| --- | --- | --- |
| `scroll_documentation_down(count?)` / `scroll_documentation_up(count?)` | Scrolls the popup where it stands — it cannot be focused without dismissing the menu | there is no popup |
| `hide_documentation()` | Closes it | there is none |
| `show_documentation()` | Nothing — always false | always |
| `is_documentation_visible()` | — | — |

`count` is a number of lines; the default is half a page.

`show_documentation()` exists so a blink.cmp keymap moves over unedited. Core
opens the popup together with the menu and offers no way to ask for it
afterwards; `completion.documentation.auto_show` is the whole switch.

### Signature help

| Function | Does | Answers false when |
| --- | --- | --- |
| `show_signature()` | `vim.lsp.buf.signature_help()` | `signature.enabled` is false, no attached server offers it, or its own signature-help window is already open |
| `hide_signature()` | Closes its signature-help window | there is none open |
| `is_signature_visible()` | — | — |

ZCmp never asks by itself. There is no window that follows you through an
argument list here — `show_signature` is the manual one, on the key you bind
it to. It declines while its own signature-help window — the one carrying
core's `textDocument/signatureHelp` focus_id, not any LSP float such as a
hover — is still open, so the shipped preset's `['<C-k>'] = { 'show_signature',
'hide_signature', 'fallback' }` toggles the window instead of re-asking
forever.
