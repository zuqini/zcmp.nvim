# Project Instructions for AI Agents

## Build & Test

zcmp is a pure-Lua Neovim plugin — there is no build step. The test suite
runs under [busted](https://lunarmodules.github.io/busted/) inside Neovim.
busted must be installed into a project-local LuaRocks tree built against
LuaJIT — see `tests/TESTING.md` for the one-time `luarocks` setup.

```bash
# Run the full suite (must run inside Neovim — it exercises real vim.* APIs)
nvim -u NONE -l tests/busted.lua

# Lint and type-check (also run in CI)
luacheck lua/ tests/
lua-language-server --check "$PWD/lua" --checklevel=Warning --configpath="$PWD/.luarc.json"
```

## Architecture Overview

zcmp configures Neovim's own completion. It does not implement matching,
ranking, menu drawing or a source protocol of its own: every source is an
entry in 'complete', and every behaviour is an option core already has.

- `init.lua` — the public API and the autocmds; every other module is an
  implementation detail. Re-exports `api.lua` one name at a time, on purpose:
  the surface is meant to be discoverable from `require('zcmp').`.
- `config.lua` — resolved `setup()` options. Usable before `setup()` runs.
  Validates against a shape table that mirrors the defaults, and merges with
  one rule of its own: a non-empty list replaces rather than extends.
- `types.lua` — annotations only. `zcmp.Config` is what a user writes (every
  field optional); `zcmp.ResolvedConfig` is what modules read (nothing unset).
- `api.lua` — the keymap commands. Each answers whether it did anything,
  which is the whole of how a key list falls through.
- `keymap.lua` — presets, dispatch, and installing/removing the buffer-local
  mappings.
- `fallback.lua` — running the mapping a key had before zcmp took it. The
  only reason zcmp does not need to know about autopair plugins.
- `buffer.lua` — which buffers zcmp drives, and the single writer of every
  option it touches: 'complete' and 'autocomplete' per buffer, 'completeopt',
  'autocompletedelay' and 'shortmess' globally. Every pass derives the whole
  value of 'complete' from current state, because the hooks that reach it
  arrive in either order.
- `sources/init.lua` — `sources.default` to a 'complete' value, and the
  provider contract: `flags`, or a module with `source()`/`completefunc()`.
- `sources/path.lua` — the path source. Only what `getcompletion()` cannot
  do: deciding where a path token starts, and resolving a relative one
  against the buffer's directory.
- `sources/snippets/` — the shipped snippet sources. `init.lua` is the
  machinery every one of them needs (start column, matching its own list,
  expanding on CompleteDone); `luasnip.lua` — which `snippets.preset =
  'luasnip'` points the provider at — and `nvim_snippets.lua` are adapters
  over it, one enumeration loop each.
- `lsp.lua` — trigger-character widening and `vim.lsp.completion`. Both
  delivery paths are deliberate; the header says why.
- `appearance.lua` — the one highlight zcmp sets.
- `commands.lua` — the `:ZCmp` user command.
- `health.lua` — `:checkhealth zcmp` diagnostics.

## Conventions & Patterns

- Code is self-documenting; add comments only where the logic is non-obvious —
  and when it is, say *why*, not what.
- `lua/` is kept type-clean (`lua-language-server --check`) and lint-clean
  (`luacheck`); both run in CI on every PR.
- Target PUC Lua 5.1 / LuaJIT — no `goto`, no 5.2+ stdlib.
- Neovim 0.12.0 is the floor. Anything newer must be feature-detected.
- The public API is blink.cmp's, for the sake of migration. A name that
  exists there and means the same thing keeps that name; anything of zcmp's
  own (`show_on_keyword`, `snippet_delete`) is documented as such.
- Nothing may re-rank, re-filter or re-draw what core produced. If a feature
  needs that, it belongs in a different plugin.
- Keys fed from a mapping go in front of the queue (`nvim_feedkeys` with the
  `i` flag): they stand in for the key that was pressed.
- Update `README.md`, `docs/` and `doc/zcmp.txt` alongside code changes.
