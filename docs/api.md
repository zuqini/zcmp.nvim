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
`vim.notify` and otherwise ignored. A table-shaped option handed a scalar
keeps its default, so a config that is wrong in one place still gets the rest.

### `zcmp.enable()`

Take over completion: write the options, install the autocmds, and attach to
every buffer already open. `setup()` calls it; call it yourself only after
`disable()`.

### `zcmp.disable()`

Hand completion back. Mappings are removed and whatever they displaced is put
back, buffers get the `'complete'` and `'autocomplete'` they had before, and
the global options ZCmp wrote are restored.

### `zcmp.is_enabled()` → `boolean`

### `zcmp.reload()`

Re-derive `'complete'` in every buffer, and start any provider module that has
arrived since. What `:ZCmp reload` runs.

### `zcmp.version` → `string`

## Sources

### `zcmp.add_source_provider(id, provider)`

Register a provider. It serves nothing until a `sources.default` or
`sources.per_filetype` list names it.

```lua
require('zcmp').add_source_provider('spell', { name = 'Spell', flags = { 'kspell' } })
```

See [docs/sources.md](sources.md) for the provider table in full.

### `zcmp.add_filetype_source(filetype, ids)`

Add one or more providers to a filetype's list, on top of `sources.default`.

```lua
require('zcmp').add_filetype_source('markdown', 'spell')
```

### `zcmp.get_lsp_capabilities(override?)` → `lsp.ClientCapabilities`

Capabilities to hand a language server. ZCmp completes through core, so these
are `vim.lsp.protocol.make_client_capabilities()` with `override` merged in —
there is nothing of ZCmp's own to announce, and a config that does not call
this loses nothing.

## Commands

Each returns whether it did anything. That is what lets a keymap entry fall
through: `{ 'select_next', 'snippet_forward', 'fallback' }` tries each in turn
until one answers `true`.

### The menu

| Function | Does | Answers false when |
| --- | --- | --- |
| `show()` | Opens the menu | it is already open, or you are not in Insert mode |
| `show_on_keyword()` | `show()`, but only with a keyword before the cursor | there is none — so a `<Tab>` bound to it still indents |
| `hide()` / `cancel()` | Closes it, restoring the text as typed | it is not open |
| `select_next()` / `select_prev()` | Moves through it | it is not open |
| `accept(opts?)` | Accepts the selected item | nothing is selected |
| `select_and_accept(opts?)` | Accepts the selected item, or the first one | the menu is not open |
| `is_visible()` / `is_menu_visible()` | — | — |

`opts.callback` is called once the item has landed (on `CompleteDone`):

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

### Snippets

| Function | Does | Answers false when |
| --- | --- | --- |
| `snippet_forward()` / `snippet_backward()` | Jumps a tabstop | there is none in that direction |
| `snippet_delete()` | Deletes the selected placeholder, leaving you in Insert | no placeholder is selected |
| `is_snippet_active(filter?)` / `snippet_active(filter?)` | — | — |

All of them go through `config.snippets`, so an engine other than
`vim.snippet` is three functions away.

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
| `show_signature()` | `vim.lsp.buf.signature_help()` | `signature.enabled` is false, or no server offers it |
| `hide_signature()` | Closes the floating preview | there is none |
| `is_signature_visible()` | — | — |

ZCmp never asks by itself. There is no window that follows you through an
argument list here — `show_signature` is the manual one, on the key you bind
it to.
