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
| `enabled` | same; runs with the buffer being decided current, so blink's no-argument form (`enabled = function() return vim.bo.buftype ~= 'prompt' end`) works, and ZCmp also passes `bufnr` |
| `keymap.preset` (`default`, `super-tab`, `enter`, `none`) | same four, plus `<CR>` as `{ 'fallback' }` in every preset but `none` — ZCmp's own addition: Enter does exactly what it did, but through ZCmp's feeder, which closes a menu that has nothing selected ahead of the key; the menu a server's answer rebuilds otherwise swallows it (see below) |
| `keymap['<Key>'] = { 'command', 'fallback' }` | same, including function entries taking `cmp`; a returned string is keys in `<Key>` notation, fed as if typed (remapped, unless it contains the key itself, which is fed non-recursively), and an empty one passes the key to the next command; an entry naming a snippet or signature command, or containing a function, is mapped in Select mode as well as Insert, as in blink, so a `snippet_active()`/`snippet_forward()` function jumps from a placeholder |
| `keymap['<Key>'] = false` | same — disables the preset's own binding for that key, the same as `{}` |
| `sources.default` | same |
| `sources.per_filetype`, including `inherit_defaults` | same |
| `sources.providers.<id>.name` / `.module` / `.opts` / `.enabled` / `.max_items` | same keys, different module contract — see [sources.md](sources.md); `.flags` and `.available` are ZCmp's own — literal 'complete' flags for a source core already implements, and a per-buffer check with no equivalent in blink's `enabled` |
| `completion.menu.auto_show` | same (becomes `'autocomplete'`) |
| `completion.documentation.auto_show` | same (becomes `popup` in `'completeopt'`) |
| `completion.list.max_items` | same (becomes each source's `^{count}`) |
| `completion.list.selection.preselect` / `.auto_insert` | same (become `preselect` / `noinsert`) |
| `snippets.active` / `snippets.jump` | same |
| `snippets.preset` | same for `'default'` and `'luasnip'`; `'mini_snippets'` is reported, not silently the default — see below |
| `snippets.expand` | same, for what ZCmp's snippet sources insert; a server's snippet items stay `vim.snippet`'s — see below |
| `signature.enabled` | same, but manual only — see below |
| `get_lsp_capabilities(override, include_nvim_defaults)` | same — see below |
| `add_filetype_source(ft, ids)` | same |
| `add_source_provider(id, provider)` | same |
| `is_enabled()` | same name, different meaning — blink's evaluates the `enabled` predicate for the current buffer; ZCmp's answers whether `enable()` has run and `disable()` has not, for every buffer alike. `:ZCmp status` reports the per-buffer answer |
| `enable()` / `disable()` | **ZCmp's own.** Take over completion (options, autocmds, every open buffer), or hand it back |
| `reload()` | same name, different job. blink's takes a provider id and re-fetches that one source; ZCmp's takes no argument and restarts every provider module |

## Commands

Most blink keymap commands exist, and answer the same true/false. Five
behave differently, two are ZCmp's own, and one (`fallback_to_mappings`) is
accepted as a synonym with no difference at all; the eight with no
equivalent are in the next table, alongside the rest of what blink.cmp has
that ZCmp does not:

| Command | Notes |
| --- | --- |
| `show_documentation` | Always falls through. Core opens the popup with the menu and offers no way to ask afterwards; `completion.documentation.auto_show` is the switch. |
| `show_signature` | Only when `signature.enabled` is set, and only on the key you press — there is no window that follows the cursor through an argument list. Declines while its own signature-help window (the `textDocument/signatureHelp` focus_id, not any LSP float) is already open, so the shipped `<C-k>` pairing with `hide_signature` toggles it instead of re-asking forever. |
| `hide` / `cancel` | Aliases in ZCmp — both feed `<C-e>`, restoring the text as typed. In blink, `hide` keeps auto-inserted text and only `cancel` reverts it. Observable only with `completion.list.selection.auto_insert = true`; core has no key of its own that closes the menu without reverting. |
| `accept` / `select_and_accept` | Take `opts.callback` only. blink's `opts.index`, for accepting an item other than the selected one, is ignored — core's own selection is the only one there is. |
| `show` | Takes no `opts` at all. blink's `providers` and `initial_selected_item_idx` are ignored — the menu is core's, not a list ZCmp assembles itself. |
| `show_on_keyword` | **ZCmp's own.** `show`, but only with a keyword before the cursor, so a `<Tab>` bound to it still indents. blink needs no equivalent: its menu opens with no delay. |
| `snippet_delete` | **ZCmp's own.** Deletes the selected placeholder and leaves you in Insert mode. |
| `fallback_to_mappings` | Accepted as a synonym for `fallback`. ZCmp has one fallback: whatever the key is mapped to without ZCmp in the way — a buffer-local mapping captured once, when ZCmp attached, a global one looked up fresh on every press — or the built-in behaviour. |

## Config with no equivalent

| blink.cmp | Why not, and what to do |
| --- | --- |
| `cmdline.*` | `'completeopt'` does not apply to the command line — that is `'wildmode'` and `'wildoptions'`, a separate mechanism. Set `wildoptions=pum` and `wildmode=noselect:lastused,full` and you have most of it, from core, with no plugin. |
| `term.*` | Same reason. |
| `completion.ghost_text` | Core has `preinsert` in `'completeopt'`, which is close but requires `fuzzy` to be unset — and the sources here depend on fuzzy matching. Not exposed. |
| `completion.menu.draw.*` (columns, treesitter highlighting, components) | Core draws the menu. `'completeitemalign'` orders the three columns it has; `appearance.kind_hl` (ZCmp's own) colours the kind one. |
| `completion.accept.auto_brackets` | Not ZCmp's job. An autopair plugin's `<CR>` still runs through `'fallback'`. |
| `completion.documentation.auto_show_delay_ms`, `window.*` | The popup is core's, and appears with the menu. |
| `completion.trigger.show_on_trigger_character` and friends | Core decides when to open, from `'autocomplete'`. `completion.menu.auto_show` is the one switch. |
| `completion.menu.auto_show_delay_ms` | Removed in ZCmp, and there is no core option left to point at: `'autocompletedelay'` is held at 0. A delay hands the first keystroke of every word to `vim.lsp.completion`'s autotrigger, and the menu it opens never asks a `'complete'` source again. See [`'autocompletedelay'` is held at 0](../README.md#autocompletedelay-is-held-at-0-and-there-is-no-option-to-change-it). |
| `sources.providers.<id>.score_offset`, `.fallbacks`, `.transform_items`, `.should_show_items`, `.min_keyword_length` | Ranking happens inside core, across all sources at once, and there is no hook in it. `max_items` and `available` are what is left. |
| `fuzzy.implementation`, `.sorts`, `.prebuilt_binaries` | There is no matcher here to configure or download; `fuzzy.enabled` — ZCmp's own, blink has no such switch — toggles core's. |
| `appearance.kind_icons`, `.nerd_font_variant` | Core draws the kind column from what a source put in `kind`. |
| `keymap` commands `insert_prev` / `insert_next` / `show_and_insert*` | `select_next`/`select_prev` already insert when `completion.list.selection.auto_insert` is on, and there is no per-command override of that flag for these to cycle against. |
| `keymap` commands `accept_and_enter` / `select_accept_and_enter` | Cmdline-mode commands; ZCmp does not drive the command line. |
| `keymap` commands `scroll_signature_up` / `scroll_signature_down` | The signature float is core's (`vim.lsp.buf.signature_help`), with no scroll of its own. |

## LSP

Delete a `vim.lsp.completion.enable(...)` call your own `LspAttach` handler
makes — `:h lsp-attach`'s example has you write one. ZCmp owns
`vim.lsp.completion` in every buffer it
drives: it drops and re-enables every completion-capable client whenever one
is newly wired, because Neovim reads `triggerCharacters` and installs
autotrigger only on a buffer handle's first `enable()`. A synchronous
handler that ran first used to win that race and silently defeat the
widening the `lsp` provider needs; any `convert`/`cmp` opts on your own call
are dropped either way.

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

A menu `vim.lsp.completion` rebuilds once a server answers obeys the same
rule, now that ZCmp writes `noselect` itself (that restart goes through
`vim.fn.complete()`, which does not force the flag the way `'autocomplete'`
does). In such a menu a `<CR>` with nothing selected opens a line through
`fallback`, which closes the menu first — Vim's own rule for `noinsert` would
otherwise end completion without a newline. That is why every preset but
`none` maps `<CR>` to `fallback`; under `none`, that Vim rule applies as
written until you add `['<CR>'] = { 'fallback' }`.

**The menu does not wait.** ZCmp holds `'autocompletedelay'` at 0 and offers
no knob for it, which is blink's cadence anyway — the menu appears as you
type. `completion.menu.auto_show = false` is the one switch, and it turns off
both `'autocomplete'` and the autotrigger. Why the knob is gone rather than
merely defaulted to 0 is in the README, under
[`'autocompletedelay'` is held at 0](../README.md#autocompletedelay-is-held-at-0-and-there-is-no-option-to-change-it):
short version, a delay lets the LSP open the menu first, and a menu opened
that way never asks a `'complete'` source again.

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
