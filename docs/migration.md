# Coming from blink.cmp

ZCmp's public surface is deliberately blink.cmp's, so a config mostly moves
over by renaming the module. What follows is what survives verbatim, what
changes shape, and what has no equivalent — with the reason, since some of the
gaps are the point of the plugin rather than missing work.

```lua
-- before
require('blink.cmp').setup(opts)
-- after
require('zcmp').setup(opts)
```

## Config that moves over unchanged

| blink.cmp | ZCmp |
| --- | --- |
| `keymap.preset` (`default`, `super-tab`, `enter`, `none`) | same four |
| `keymap['<Key>'] = { 'command', 'fallback' }` | same, including function entries taking `cmp` |
| `sources.default` | same |
| `sources.per_filetype`, including `inherit_defaults` | same |
| `sources.providers.<id>.name` / `.module` / `.opts` / `.enabled` / `.max_items` | same keys, different module contract — see [sources.md](sources.md) |
| `completion.menu.auto_show` | same (becomes `'autocomplete'`) |
| `completion.documentation.auto_show` | same (becomes `popup` in `'completeopt'`) |
| `completion.list.max_items` | same (becomes each source's `^{count}`) |
| `completion.list.selection.preselect` / `.auto_insert` | same (become `preselect` / `noinsert`) |
| `snippets.active` / `snippets.jump` | same |
| `snippets.preset` | same for `'default'` and `'luasnip'`; `'mini_snippets'` is reported, not silently the default — see below |
| `snippets.expand` | same, for what ZCmp's snippet sources insert; a server's snippet items stay `vim.snippet`'s — see below |
| `signature.enabled` | same, but manual only — see below |
| `get_lsp_capabilities(override)` | same |
| `add_filetype_source(ft, ids)` | same |
| `add_source_provider(id, provider)` | same |

## Commands

Every blink keymap command exists, and answers the same true/false. Two
behave differently and two are ZCmp's own:

| Command | Notes |
| --- | --- |
| `show_documentation` | Always falls through. Core opens the popup with the menu and offers no way to ask afterwards; `completion.documentation.auto_show` is the switch. |
| `show_signature` | Only when `signature.enabled` is set, and only on the key you press — there is no window that follows the cursor through an argument list. |
| `show_on_keyword` | **ZCmp's own.** `show`, but only with a keyword before the cursor, so a `<Tab>` bound to it still indents. blink needs no equivalent: its menu opens with no delay. |
| `snippet_delete` | **ZCmp's own.** Deletes the selected placeholder and leaves you in Insert mode. |
| `fallback_to_mappings` | Accepted as a synonym for `fallback`. ZCmp has one fallback: whatever the key was mapped to before it attached, or the built-in behaviour. |

## Config with no equivalent

| blink.cmp | Why not, and what to do |
| --- | --- |
| `cmdline.*` | `'completeopt'` does not apply to the command line — that is `'wildmode'` and `'wildoptions'`, a separate mechanism. Set `wildoptions=pum` and `wildmode=noselect:lastused,full` and you have most of it, from core, with no plugin. |
| `term.*` | Same reason. |
| `completion.ghost_text` | Core has `preinsert` in `'completeopt'`, which is close but requires `fuzzy` to be unset — and the sources here depend on fuzzy matching. Not exposed. |
| `completion.menu.draw.*` (columns, treesitter highlighting, components) | Core draws the menu. `'completeitemalign'` orders the three columns it has; `appearance.kind_hl` colours the kind one. |
| `completion.accept.auto_brackets` | Not ZCmp's job. An autopair plugin's `<CR>` still runs through `'fallback'`. |
| `completion.documentation.auto_show_delay_ms`, `window.*` | The popup is core's, and appears with the menu. |
| `completion.trigger.show_on_trigger_character` and friends | Core decides when to open, from `'autocomplete'` and `'autocompletedelay'`. `completion.trigger.delay_ms` is the one knob. |
| `sources.providers.<id>.score_offset`, `.fallbacks`, `.transform_items`, `.should_show_items`, `.min_keyword_length` | Ranking happens inside core, across all sources at once, and there is no hook in it. `max_items` and `available` are what is left. |
| `fuzzy.implementation`, `.sorts`, `.prebuilt_binaries` | There is no matcher here to configure or download; `fuzzy.enabled` toggles core's. |
| `appearance.kind_icons`, `.nerd_font_variant` | Core draws the kind column from what a source put in `kind`. |

## Snippets

`preset = 'default'` needs no translation: the engine is `vim.snippet`, which
is what `vim.lsp.completion` expands a server's snippet items with anyway.

`preset = 'luasnip'` moves over unedited too, and means what it means in
blink: `expand`, `active` and `jump` default to LuaSnip's, and the `snippets`
provider points at a LuaSnip source ZCmp ships. The one behavioural
difference from blink: a language server's snippet items still expand through
`vim.snippet` — `vim.lsp.completion` owns that accept, not ZCmp — so the
preset's functions ask LuaSnip first and fall through to `vim.snippet`, and
the snippet keymap commands walk either session.

`preset = 'mini_snippets'` has no ZCmp equivalent yet; `setup()` reports it
rather than silently behaving like `'default'`. The substitution is
`snippets.expand`, `snippets.active` and `snippets.jump` written out, plus a
`snippets` provider module for the menu candidates.

`sources.default`'s `snippets` entry is a separate thing — the source that
puts snippet candidates in the menu. blink's is built in; ZCmp's is a
provider pointing at zsnip.nvim by default, swapped by the `'luasnip'` preset
to ZCmp's own LuaSnip source, and swappable for any module with a `source()`
or `completefunc()` — ZCmp ships one for nvim-snippets as well. See
[sources.md](sources.md#snippets).

## Two behaviours to expect

**`<CR>` and preselect.** `'autocomplete'` forces `noselect` on, and
`preselect` in `'completeopt'` overrides it only for items a source *marked*.
Core's buffer scanners mark nothing, so a buffer word is not under the cursor
until you press `<C-n>`. blink always had something selected. If you want the
old feel, bind `select_and_accept` rather than `accept`:

```lua
keymap = { preset = 'enter', ['<CR>'] = { 'select_and_accept', 'fallback' } },
```

On Neovim 0.12.0 this is not a preference: the `preselect` flag does not
exist there, so nothing is ever selected and `select_and_accept` is the only
binding that accepts anything.

**The menu waits.** `completion.trigger.delay_ms` (200 by default) is
`'autocompletedelay'`: sources do not run until typing pauses for that long,
which is also what bounds how often a directory is listed and a server asked.
blink's menu appears immediately and filters asynchronously. Set it to 0 for
blink's cadence, at the cost of running every source on every keystroke.

## Keeping both installed

Don't. Two engines write `'complete'`, map insert mode and call `complete()`,
and the result is neither. `:checkhealth zcmp` warns when it sees blink.cmp,
nvim-cmp or mini.completion loaded alongside.

Switching between them from one config is fine, as long as only one runs:

```lua
local engine = vim.env.NVIM_CMP_ENGINE or 'zcmp'

{ 'saghen/blink.cmp', enabled = engine == 'blink' },
{ 'zuqini/zcmp.nvim', enabled = engine == 'zcmp', config = function()
  require('zcmp').setup({ ... })
end },
```
