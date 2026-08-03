# Review decisions

Accepted tradeoffs reviewers should not re-flag. Before adding an entry, search for an existing one and append to its `History:` instead.

Schema: `title` / `Flagged` / `Decision` (required); `Type` / `Anchor` / `Filed` / `History` / `Revisit when` (optional). Full lifecycle in `~/.claude/skills/review/SKILL.md`.

Most of this file was ported with the code from a Neovim config's `lua/plugins/lsp/utils/builtin-cmp.lua`, where these decisions were made and measured.

## Recurring false flags

## Decisions

## Both autotrigger and 'o' in 'complete' are on, and neither is redundant

- Flagged: `lsp.attach()` calls `vim.lsp.completion.enable(..., { autotrigger = true })` *and* the `lsp` provider puts `o` in 'complete'. Two ways of asking the same server on the same keystroke; drop one.
- Anchor: `lua/zcmp/lsp.lua` — `M.attach`; `lua/zcmp/config.lua` — the `lsp` provider
- Decision: keep both. They fail in opposite directions and the failures are measured, not theoretical.
  - `'o'` alone: server items land in the same ranked menu as ours (that is the whole point -- neovim#35257 / PR #35346), but the server is asked once per completion cycle. After `vim.` you get whatever came back for the bare prefix and nothing narrows it: typing `tbl_g` leaves a menu of 103 items with 0 matching, because `vim.fn.complete()` has taken the cycle and the `'complete'` sources are done (neovim#32428). `vim.tbl_get` is unreachable by typing through the dot.
  - autotrigger alone: re-asks on every widened trigger character, so `vim.tbl_g` comes back with 21 items including `tbl_get` -- but a plain keyword gets no server items at all. Typing `l` gives `Snippet=11 Text=172` and nothing from lua_ls.
  - Together: `l` gives `Field=1 Function=3 Keyword=1 Snippet=12 Text=172 Variable=1`, and `vim.tbl_g` still finds `tbl_get`.
- The cost is some duplicate requests per keystroke, which `Context:cancel_pending_requests()` in `vim/lsp/completion.lua` already handles. Cheaper than either failure.
- The trigger-character widening exists for the same reason: without every letter in `triggerCharacters`, autotrigger never fires on a plain keyword and the second half of this is dead.
- Revisit when: neovim#32428 lands. If `complete()` stops owning the cycle, `'o'` alone should cover both and autotrigger can go.

## A word offered by both a server and the buffer can appear twice

- Flagged: typing `alph` over `local alphabetical = 1` in a lua buffer gives a two-item menu -- `alphabetical/Text` from core's buffer scanner and `alphabetical/Variable` from the server. Reviewers reach for filtering our sources against what the server already offered.
- Anchor: `lua/zcmp/sources/init.lua` — `M.resolve`
- Decision: accepted, and not fixable from here. Core dedups identical words *across 'complete' sources*, which is why the flag sources never duplicate each other. LSP items do not arrive that way: `vim.lsp.completion`'s `trigger()` rebuilds the menu through `vim.fn.complete()`, keeping the previous items (ours, identified by having no `client_id`) and appending the fresh server ones with no comparison between the two sets -- see `runtime/lua/vim/lsp/completion.lua`, the `prev_matches` filter. The duplicate is structural to the reconstruction.
- A previous engine did filter, with an `lsp_words()` reading `complete_info({'items'})` on every request -- measured at 2.1ms per response at 2k items and 11.5ms at 10k, and it still lagged a keystroke so duplicates showed anyway. Paying that to hide a cosmetic repeat is exactly the "work against core" this plugin exists to stop doing.
- Filed: upstream, do not refile -- neovim/neovim#36166 (merged Oct 2025) deduplicates *within* LSP results; it does not compare them against non-LSP sources. The clean fix is upstream in `trigger()`, not here.
- Revisit when: `trigger()` dedups `prev_matches` against the incoming set, or neovim#32428 lands and LSP stops going through `complete()` at all.

## Buffer words and directory listings are core's, not ours

- Flagged: there is an `F` source for paths but none for buffer words, and the path source calls `vim.fn.getcompletion()` rather than listing directories itself. Looks like two different approaches to the same job.
- Anchor: `lua/zcmp/sources/path.lua` — `M.items`; `lua/zcmp/config.lua` — the `buffer` provider
- Decision: both halves were hand-rolled once, when everything reached the menu through `vim.fn.complete()` -- which takes the cycle and never consults core's own sources. Hand-rolling was the only option then; `'complete'` removed the constraint.
  - Buffer words are `.`, `w` and `b`. Measured equivalent on the same content: core's `.^200,w,b` with `fuzzy` and a 153-line scanner both answered `alphabetical` for `alph`. What went with the scanner: a 20k-line scan cap, a stale-cache-plus-background-rescan layer, and `MIN_WORD_LEN = 3` -- core has no minimum, so one- and two-character words now appear.
  - Directory listings are `vim.fn.getcompletion(pat, 'file')`: it appends `/` to directories, hides dotfiles until one is asked for, and expands `~/` -- every rule 121 lines carried, and in C, so an mtime-keyed `dir_cache` is gone too.
- What could not be delegated is the whole of what remains: `split()` decides where a path token starts in a line and rejects `//`, `a / b` and url schemes -- `getcompletion()` takes a pattern, not a cursor. `resolve_dir()` stays for the same reason: getcompletion resolves against the cwd, and a relative token belongs to the buffer's own directory.
- The cost of the path half is known and accepted: pathing into a wide directory is expected to be slower, and ordinary typing is unaffected -- `split()` bails before `getcompletion()` whenever the token has no `/`, measured at 0 calls and 0.00 ms for `local x = 1`, `vim.lsp.completion.enable` and `require 'plugins.lsp.utils'`. A 5-entry directory is 0.06 ms; only a wide one bites. Do not re-flag the main-thread listing without a new argument. `getcompletion()` stats every entry to decide the trailing `/` and has no early exit, so `max_items` truncates *after* the syscall and bounds nothing that costs. Measured: 5000-entry directory 22 ms, 20000-entry 97 ms, `~/.cache/nvim/luac` 44 ms -- against `fs_scandir` at 2.1 ms for the same 5000 (and ~0.1 ms if stopped at 250, which scandir can do and getcompletion cannot). Typing the `/` is always the worst keystroke and is unavoidable. Narrowing only rescues it when names diverge early: `/usr/bin` drops 8.7 -> 0.6 ms at one character, but a directory of `file_0001…` stays at 22 ms through four. The fix is not a cache -- it is `vim.uv.fs_scandir` with an early exit, which also returns the entry type directly and so needs no stat at all. Held off because it re-hand-rolls dotfile hiding and the `/` suffix that this entry deliberately delegated.

## `M.items` returns nil vs an empty list

- Flagged: `M.items` returns `nil` for "not a path context" and `{}` for "path context, nothing matched", while `completefunc` collapses both with `or {}`.
- Anchor: `lua/zcmp/sources/path.lua` — `M.items` / `split`
- Decision: keep. `nil` means "the cursor is not in a path", which is the same question `split` answers for `M.start`; keeping the two in agreement is worth more than the line it saves.
- History: this previously defended a third `nil`, `ctx.keyword ~= dir .. segment`, as "an assertion rather than a filter". **That was wrong, and the source was dead because of it.** `a:base` is the text located in the *first* call of a completion cycle (`:h complete-functions`) and is not re-derived on `refresh = 'always'` re-invocations, while `dir`/`segment` were recomputed from the live line. Measured in a pty: typing `abcd`, `findstart` is re-called each keystroke with the live line but `base` stays frozen at `"a"`. So the two disagreed on every keystroke after the first and `M.items` returned `nil` forever. Fixed by deriving from the live line and deleting the guard, which is why `M.items` takes no argument at all.

## `<CR>` accepts only what a source preselected, and that is not a bug

- Flagged: typing `alph` over `local alphabetical = 1` and pressing `<CR>` opens a line instead of accepting the buffer word, even though the menu is up with `alphabetical` in it. Reads as `accept` being broken.
- Anchor: `lua/zcmp/api.lua` — `M.accept` / `has_selection`; `lua/zcmp/buffer.lua` — `M.completeopt`
- Decision: correct as designed, and core's rule rather than ours. `'autocomplete'` forces `noselect` on; `preselect` in 'completeopt' overrides it *only* for items whose `preselect` field a source set (`:h 'completeopt'`). Our path source sets it, and `vim.lsp.completion` passes the server's through (`runtime/lua/vim/lsp/completion.lua`, `preselect = item.preselect`). Core's `.`/`w`/`b` scanners set nothing, so a buffer word is genuinely not selected and there is nothing for `accept` to take.
- `select_and_accept` is the answer, and is why both exist: it takes the first item when none is selected. blink.cmp draws the same distinction for the same reason.
- Do not "fix" this by dropping `noinsert`, which is load-bearing for the LSP path (`vim.lsp.completion` calls `vim.fn.complete()` itself and that path honours it -- without it `vim.` becomes `vim.F`), and do not reach for `preinsert`, which requires `fuzzy` to be unset.
- Covered by `integration_test.lua`: `<CR>` accepts a preselected path item, opens a line with no selection, and takes the first buffer word when bound to `select_and_accept`.

## Keys fed from a mapping use the 'i' flag

- Flagged: `nvim_feedkeys(keys, 'in', false)` -- the `i` ("insert before pending input") flag looks like cargo cult next to the usual `'n'`.
- Anchor: `lua/zcmp/api.lua` — `feed`; `lua/zcmp/fallback.lua` — `feed`
- Decision: load-bearing, and it was a real bug before. These keys *stand in for* the key that was pressed, so they belong in front of whatever is still queued. With `'n'`, a `<Tab>` pressed from a macro or `feedkeys()` sequence runs after the rest of the sequence: typing `<Tab>x` produced `x<Tab>` and a `<CR>` fallback interleaved into `zz60qIRED`. Found by the child-Neovim integration specs, which feed a whole sequence at once; a human typing one key at a time never sees it.
- `escape_ks` is `false` on purpose too: the keys have already been through `vim.keycode()`, and escaping them again turns `<S-Tab>` and every other K_SPECIAL key into literal bytes.

## `show_documentation()` does nothing and always returns false

- Flagged: a public API function whose whole body is `return false`. Dead code.
- Anchor: `lua/zcmp/api.lua` — `M.show_documentation`
- Decision: deliberate, and documented in three places. Core opens the documentation popup together with the menu when 'completeopt' has `popup`, and offers no API to ask for it afterwards -- `completion.documentation.auto_show` is the entire switch. The function exists so that a blink.cmp keymap (`['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' }`, which is blink's own default preset) moves over unedited and simply falls through to the next command. Removing it would make every such keymap warn about an unknown command.
- `hide_documentation()` next to it is not a no-op -- it closes the popup window -- so the pair is not symmetric, and that asymmetry is core's.

## fallback executes another plugin's mapping by hand

- Flagged: `fallback.lua` reads a maparg dict, evaluates `expr`, honours `replace_keycodes` and `noremap`, and feeds the result -- re-implementing what Vim would do if the key were simply not mapped.
- Anchor: `lua/zcmp/fallback.lua`
- Decision: there is no other way. ZCmp's mapping is buffer-local and must win, so the key never reaches the global mapping on its own; and returning the key from an expr mapping cannot reach it either, because that resolution is not remapped. Capturing the displaced mapping and running it is what every completion plugin with a `fallback` command does.
- The guard against a right-hand side that begins with its own left-hand side is not theoretical: `remap` plus such an rhs is an immediate loop.
- `lhsrawalt` is checked alongside `lhsraw` because a key with a modifier is stored in its own encoding -- `<C-j>` is `<80><fc>\4J`, with `\n` kept alongside. Matching only `lhsraw` misses every such key, which is how this was found.

## `resolve_dir` matches `~/` and not `~user/`

- Flagged: `vim.startswith(dir, '~/')` misses `~user/`, which then falls to the relative branch and resolves against the buffer's directory -- so `~root/` silently offers nothing. Reviewers reach for widening the test to a leading `~`, or for `vim.fs.normalize` / `vim.fn.expand`.
- Anchor: `lua/zcmp/sources/path.lua` — `resolve_dir`
- Decision: keep the `~/`-only test. It is what stops `vim.fs.normalize` mangling the token: measured on 0.13.0-dev, `vim.fs.normalize('~user/')` answers `/Users/zuqini` **`user`** -- it substitutes the home directory for the leading `~` and keeps the username as part of the path. Widening the branch turns "no matches" into a listing of the wrong directory, which is worse.
- `vim.fn.expand('~root/')` does resolve it correctly (`/var/root/`), but `expand()` also applies wildcards, `%`, `#` and `$VAR`, and the token character class admits `$` -- so routing paths through it makes `$HOME/f` and a stray `%` expand as a side effect of a fix for a form of path that modern systems barely have. Not worth the surface.
- Revisit when: `vim.fs.normalize` handles `~user` (it would then be a one-word change), or a user asks for it.

## The snippets provider's default `opts` carry only `complete = false`

- Flagged (originally): every other built-in provider caps with `max_items`; the `snippets` one carried `limit = 30` in `opts` instead. Looks like an oversight.
- Anchor: `lua/zcmp/config.lua` — the `snippets` provider
- Decision (revised 2026-08): the default passes **no** `limit` and no `documentation` at all. zsnip resolves a `nil` field from its own `setup()`, so an explicit value here silently overrode the place a user actually configures snippets — `documentation = false` also fought zcmp's own `completion.documentation.auto_show = true`. Preferences belong to zsnip; the one key zcmp keeps is `complete = false`, which is coordination, not preference: `buffer.lua` is the single writer of `'complete'`, so zsnip must not append itself.
- A user who *does* want a per-source override may still put `limit`/`documentation` in `opts` — they go to the module verbatim and beat zsnip's `setup()`, which is why the default must not use them. Do not re-flag the remaining asymmetry with `max_items`: `max_items` is core's `^{count}`, truncating after the source answers; a `limit` in `opts` truncates before the items are built.

## The `lsp` provider is the one wired by name from the buffer layer

- Flagged: `buffer.lua` names `'lsp'` as a string literal, and `sources.provider()` exists to serve that one call. The provider contract has no `attach(bufnr)`/`detach(bufnr)`, so `lsp.lua`'s whole per-buffer lifecycle -- `attach`/`sync`/`detach`, the `wired` and `declared` tables -- is something no other provider could express. Reviewers reach for widening the contract and iterating providers instead of naming one.
- Anchor: `lua/zcmp/buffer.lua` — `wire`; `lua/zcmp/sources/init.lua` — `M.provider`
- Decision: deferred on purpose, not overlooked. The contract today is what every source zcmp ships actually needs: `flags`, `source()`, `completefunc()`, and a `enable()` that runs once. Exactly one provider needs per-buffer work, and a hook designed against one consumer is a hook designed against a guess -- `vim.lsp.completion`'s shape (refcount trigger characters across buffers, re-sync on LspAttach *and* on the source list changing) is unlikely to be the shape the second one wants.
- The costs are real and bounded: renaming the `lsp` provider id, or defining a second server-backed provider, silently loses the `vim.lsp.completion` wiring with no warning; and `lsp.lua` is the one module with three inbound edges (`config.lua`'s `available` closure, `buffer.lua`, `init.lua`).
- Revisit when: a second provider needs to do anything when it joins or leaves a buffer. That is the point at which two consumers exist and the hook can be designed against both -- and it must be decided *then*, not by editing `buffer.lua` a second time.

## `known()` writes 'completeopt' to find out which flags this Neovim has

- Flagged: `known()` sets `vim.go.completeopt` four times and restores it, and is reached from `M.completeopt()`, which `:checkhealth zcmp` calls purely to compare against the current value. A read-only diagnostic mutating a global option and firing `OptionSet` four times with values nobody asked for.
- Anchor: `lua/zcmp/buffer.lua` — `known` / `M.completeopt`
- Decision: keep. 'completeopt' raises E474 rather than ignoring a flag it does not know, and nothing reports its accepted values -- `nvim_get_option_info2` answers scope and type, not the value set. Trying each under `pcall` is the only probe there is, and `preselect` is newer than the 0.12.0 floor, so it has to be asked rather than assumed.
- Bounded by construction: once per session, four writes, saved before and restored after, and `menuone` is never in question because every probe is written against it. Covered by `buffer_test.lua`.
- Revisit when: Neovim reports an option's accepted values, at which point the probe becomes a read and `M.completeopt()` becomes the pure derivation it looks like.

## An explicit `per_filetype` list in setup() replaces what a registration added

- Flagged: `zcmp.add_filetype_source('lua', { 'lazydev' })` followed by a `setup()` that writes `per_filetype.lua` leaves the registration out of the resolved list, while `doc/zcmp.txt` and `docs/api.md` say a call before `setup()` "survives it". Reviewers reach for moving the `per_filetype` half of `apply_additions()` to run on the merged result so `add_ids` layers registrations on top.
- Anchor: `lua/zcmp/config.lua` — `apply_additions` / `merge`
- Decision: correct as it stands, and the two sentences do not conflict. "Survives" means the registration is not lost by *call order* -- before or after `setup()` reaches the same resolved options, which is the whole reason `additions` exists. What an explicit list then does to it is the merge rule, stated in the same docstring: registrations "go underneath, so that an explicit `opts` still wins", and a non-empty list replaces rather than extends. A user who writes `per_filetype.lua = { 'mine' }` has said which sources lua gets.
- Layering registrations on top of the merged result would make `sources.default`'s rule and `per_filetype`'s rule disagree, and would leave no way to *remove* a source some plugin registered -- the list would grow monotonically with every plugin installed.
- `inherit_defaults = true` is the additive form and is what a registration creates, so a user who wants both writes their own ids and inherits the rest.
- Covered by `config_test.lua`: "replaces a filetype list a registration had added to", and "lets an explicit setup() win over an earlier registration" for the provider half.
