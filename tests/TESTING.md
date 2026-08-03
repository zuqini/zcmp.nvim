# ZCmp.nvim Test Suite

The suite runs under [busted](https://lunarmodules.github.io/busted/). Because
the tests exercise real Neovim APIs (options, buffers, keymaps, LSP clients,
the completion menu), busted runs *inside* Neovim via `nvim -l` rather than
under a standalone Lua interpreter.

## Running Tests

### One-time setup

busted and its dependencies are installed into a project-local LuaRocks tree
(`.luarocks/`, gitignored). Install it built against LuaJIT so its native
dependency (luafilesystem) is ABI-compatible with Neovim's bundled LuaJIT:

```bash
luarocks --lua-version=5.1 --lua-dir=<luajit-prefix> --tree .luarocks install busted 2.3.0
```

`<luajit-prefix>` is your LuaJIT install prefix — e.g. `$(brew --prefix luajit)`
on macOS.

### Run all tests

From the project root:

```bash
nvim -u NONE -l tests/busted.lua
```

The command exits 0 when the suite is green and non-zero when any test fails.
busted's CLI flags are passed through:

```bash
nvim -u NONE -l tests/busted.lua --filter "keymap"
nvim -u NONE -l tests/busted.lua --shuffle
```

The keystroke-driven specs each start a child Neovim and wait on real timers,
which is most of the suite's wall-clock time; `--filter` past
`integration_test.lua` while iterating on the rest.

## Test Structure

- `tests/busted.lua` — bootstraps busted to run in-process under `nvim -l`.
- `tests/*_test.lua` — native busted spec files, discovered through the
  `.busted` pattern.
- `tests/helpers.lua` — throwaway buffers and directories, plus the stubs a
  headless runner needs: `pum()` stands in for a completion menu (there is no
  UI, so `pumvisible()` and `complete_info()` are replaced), `keys()` records
  what zcmp fed instead of letting it reach a typeahead nothing reads,
  `mode()` answers Insert where the runner is really in Normal, and
  `settle()` waits out the `vim.schedule()` every attach goes through.
  `reset()`/`cleanup()` give each test a fresh config with no buffer attached,
  and undo every stub on both the passing and the failing path.
- `tests/child.lua` — runs a fragment in a *child* Neovim and hands back what
  it emitted. Insert-mode completion cannot be exercised in-process: `nvim -l`
  has no main loop, so `nvim_feedkeys(..., 'n')` queues keys nothing reads,
  and the `'x'` flag runs them in a nested exec where textlock forbids the
  `complete()` call that is the whole point. Its `scenario()` types into a
  buffer, waits for the menu, then sends whatever accepts or dismisses it —
  with the `'m'` flag, since keys that are not remapped never reach the
  mappings under test.

| Spec | Covers |
| --- | --- |
| `config_test.lua` | Defaults, merging (a list replaces, a provider merges), and what `setup()` reports about a config that is wrong |
| `path_test.lua` | The path source: where a token starts, what it lists, and the shapes that are not paths at all |
| `sources_test.lua` | `sources.default` to a 'complete' value: order, caps, per-filetype lists, provider modules that are missing or serve nothing |
| `keymap_test.lua` | Presets, command dispatch order, and `'fallback'` — reaching a displaced mapping and putting it back |
| `api_test.lua` | Every keymap command, against a stubbed menu, snippet session and documentation popup |
| `buffer_test.lua` | 'completeopt' derivation, the global options, and which buffers attach, detach and re-derive |
| `lsp_test.lua` | Trigger-character widening, capabilities, and a real in-process client arriving and leaving |
| `health_test.lua` | Every `:checkhealth zcmp` section, against a recording `vim.health` stub |
| `commands_test.lua` | `:ZCmp` dispatch, completion, status output, enable/disable/reload |
| `integration_test.lua` | Real keystrokes in a child Neovim: what the menu offers, what accepting puts in the buffer, and which key does what |

## Test Environment

Tests build the state they need and hand it back on the way out:

```lua
local helpers = require('helpers')

describe("Your Test Suite", function()
  before_each(helpers.reset)
  after_each(helpers.cleanup)

  it("serves what the source list names", function()
    local bufnr = helpers.buffer({ 'alphabetical' })
    require('zcmp').setup({ sources = { default = { 'buffer' } } })
    helpers.settle(bufnr)

    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)
end)
```

### Available Assertions

Assertions come from busted's bundled [luassert](https://github.com/lunarmodules/luassert):

- `assert.are.equal(expected, actual)` — `==` (identity) equality
- `assert.are.same(expected, actual)` — deep/recursive equality
- `assert.is_true(value)` / `assert.is_false(value)` — strict boolean equality
- `assert.is_nil(value)` / `assert.is_not_nil(value)` — nil checks
- `assert.contains(tbl, value)` — list membership (registered by `helpers.lua`)

## Notes

- CI runs the suite on Neovim 0.12.0 and nightly on every push to `main` and
  every pull request; see `.github/workflows/tests.yml`. CI's LuaRocks is
  already bound to LuaJIT, so it installs busted with just
  `luarocks install --tree .luarocks busted 2.3.0`.
