<h1 align="center">ZCmp.nvim</h1>
<div align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/zuqini/zcmp.nvim/tests.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=tests&labelColor=1e1b4b"> <img src="https://img.shields.io/github/issues/zuqini/zcmp.nvim?style=for-the-badge&logo=github&logoColor=white&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/last-commit/zuqini/zcmp.nvim?style=for-the-badge&logo=neovim&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/license/zuqini/zcmp.nvim?style=for-the-badge&logo=opensourceinitiative&logoColor=white&color=8b5cf6&labelColor=1e1b4b">
</div>

<p align="center">A completion engine's configuration, for the completion engine Neovim already ships.</p>

**[Why ZCmp?](#why-zcmp)** | **[Quick start](#quick-start)** | **[Sources](#sources)** | **[Keymaps](#keymaps)** | **[API](docs/api.md)** | **[Providers](docs/sources.md)** | **[Coming from blink.cmp](docs/migration.md)**

## Why ZCmp?

Neovim 0.12 completes on its own. It opens the menu as you type
(`'autocomplete'`), takes a Lua function as a source (`'complete'`),
fuzzy-matches, ranks and time-slices what the sources answer, draws the
documentation popup, and asks language servers through
`vim.lsp.completion`. What it does not ship is a configuration for any of
that — which is the part everyone actually installs a completion plugin for.

ZCmp is that layer and nothing more. There is no engine here: no matcher of
its own, no menu drawing, no scoring, no binary to build. What you get is one
blink.cmp-shaped table over the seven options and two APIs that already do the
work.

| | Engine | Menu | Sources | Ships |
| --- | --- | --- | --- | --- |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | its own (Rust matcher) | its own | its own protocol | a binary, or `cargo` |
| [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) | its own | its own | its own protocol | ~7k lines of Lua |
| [mini.completion](https://github.com/nvim-mini/mini.completion) | core's | core's, plus its own info/signature windows | the omnifunc, and a fallback | one module |
| **ZCmp** | **core's** | **core's** | **`'complete'` entries** | **configuration** |

Concretely, what that buys and what it costs:

- **Every source ranks in one menu.** `'complete'` takes core's buffer
  scanners, function sources and the LSP omnifunc together, fuzzy-matches
  across all of them and caps each one separately (`.^100`). Nothing in ZCmp
  re-ranks afterwards, because there is no afterwards.
- **Each source anchors where it wants.** A `'complete'` function source
  chooses its own start column, so a path (`./al`) and a snippet trigger
  (`<div`, `#!`) replace what they should — something `vim.fn.complete()`,
  with one start column for the whole menu, cannot express.
- **A path source**, which core has none of: it finds where a path token
  begins in a line and hands the listing itself to `getcompletion()` — the
  trailing `/`, hidden dotfiles, `~/` expansion and all. Relative tokens
  resolve against the buffer's directory, not the cwd.
- **Snippets are [zsnip](https://github.com/zuqini/zsnip.nvim)'s**, through
  its own `'complete'` source, which expands with `vim.snippet`. One line of
  config, no adapter.
- **Both LSP delivery paths at once**, because each covers what the other
  misses: the `o` flag merges server items into the ranked menu but asks once
  per completion cycle, while `vim.lsp.completion`'s autotrigger re-asks per
  trigger character but answers nothing for a plain keyword. ZCmp widens the
  server's trigger characters to every letter, which is what makes the second
  fire at all.
- **Keys that give themselves back.** Every mapping is buffer-local and every
  `'fallback'` runs whatever the key was mapped to before — an autopair
  plugin's `<CR>` keeps working because ZCmp finds it, not because ZCmp knows
  it exists.
- **What it does not do:** command-line completion (that is `'wildoptions'`,
  a different mechanism entirely), a signature window that follows you through
  an argument list, ghost text, per-source scoring, or drawing anything. If
  you want those, blink.cmp is a good plugin and this is the wrong one.

## Requirements

- Neovim 0.12.0+
- Optional: [zsnip.nvim](https://github.com/zuqini/zsnip.nvim) for the
  `snippets` source

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
| `snippets` | `zsnip.complete`, expanded by `vim.snippet` | zsnip.nvim |
| `buffer` | Core's own scanners: this buffer, other windows, other buffers | nothing |

`sources.default` is both the list and the priority order — it becomes
`'complete'` in the order you write it.

```lua
require('zcmp').setup({
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = { markdown = { 'path', 'buffer' } },
    providers = {
      buffer = { max_items = 50, opts = {} },
      -- Anything 'complete' understands is a provider:
      spell = { flags = { 'kspell' } },
    },
  },
})
```

A provider with a `module` is one you can write yourself — a module with a
`completefunc`, which is roughly twenty lines. See
[docs/sources.md](docs/sources.md).

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
  },
})
```

Each entry is tried in order until one reports that it did something.
`'fallback'` is the escape hatch: it runs whatever the key was mapped to
before ZCmp attached — a buffer-local mapping, a plugin's global one, or the
built-in behaviour of the key. That is how `<Tab>` still indents, `<CR>` still
opens a line, and an autopair plugin still pairs.

An entry may also be a function, which is handed the API:

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
        auto_insert = false,              -- insert it before it is accepted
      },
    },
    trigger = { delay_ms = 200 },         -- 'autocompletedelay'
  },

  fuzzy = { enabled = true },             -- `fuzzy` in 'completeopt'

  snippets = {
    preset = 'default',                   -- vim.snippet; override the three
    expand = function(body) vim.snippet.expand(body) end,
    active = function(filter) return vim.snippet.active(filter) end,
    jump = function(direction) vim.snippet.jump(direction) end,
  },

  signature = { enabled = false },        -- whether `show_signature` does anything
  appearance = { kind_hl = 'Special' },   -- colour for the menu's kind column
})
```

An unknown key, or a known one of the wrong type, is reported with
`vim.notify` and otherwise ignored — the rest of the config still applies.

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

## Commands

| Command | What it does |
| --- | --- |
| `:ZCmp` or `:ZCmp status` | What is serving this buffer, and what `'complete'` came out as |
| `:ZCmp enable` / `:ZCmp disable` | Take over completion, or hand it back |
| `:ZCmp reload` | Re-read the source list, and start a provider module that has arrived since |

`:checkhealth zcmp` answers the questions an empty menu raises: whether the
engine is enabled, whether this buffer is one ZCmp drives, which sources
answered for it and which could not (a provider whose module is not
installed says so), and whether another completion engine is loaded alongside.

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
