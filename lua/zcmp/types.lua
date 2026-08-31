---Type declarations for ZCmp.nvim.
---
---Loaded for its annotations only; the module itself is empty.

---@class zcmp.Config
---@field enabled? fun(bufnr?: integer): boolean Whether ZCmp drives completion in a buffer (default: `buftype` is empty); runs with that buffer current, so blink.cmp's no-argument form (reading `vim.bo`/`vim.b` un-indexed) works unedited
---@field keymap? zcmp.KeymapConfig
---@field sources? zcmp.SourcesConfig
---@field completion? zcmp.CompletionConfig
---@field fuzzy? { enabled?: boolean } Fuzzy matching, i.e. `fuzzy` in 'completeopt' (default true). ZCmp's own: blink.cmp has no switch for its matcher
---@field snippets? zcmp.SnippetsConfig
---@field signature? { enabled?: boolean } Whether |zcmp.show_signature()| does anything (default false)
---@field appearance? { kind_hl?: string|false } Highlight group the kind column borrows its colour from (default `'Special'`)

---Keys mapped in every buffer ZCmp attaches to, on top of a preset. Each
---value is a list of commands tried in order until one reports that it did
---something; `'fallback'` hands the key to whatever it is mapped to without
---ZCmp in the way -- a buffer-local mapping captured once, when ZCmp
---attached, a global one looked up fresh on every press -- and always
---answers, so nothing written after it in a list can run.
---@class zcmp.KeymapConfig
---@field preset? zcmp.KeymapPreset
---@field [string] zcmp.Command[]|false `false` disables a preset's own binding for that key, the same as `{}`

---@alias zcmp.KeymapPreset "default" | "super-tab" | "enter" | "none"

---A keymap entry: the name of a |zcmp-commands| function, or a function
---taking the commands table and returning whether it handled the key -- or,
---per blink.cmp's own contract, a string of keys in |<Key>| notation, fed as
---if typed. An empty string is the same as `false`.
---@alias zcmp.Command
---| string
---| fun(cmp: table): boolean|string|nil

---@class zcmp.SourcesConfig
---@field default? string[] Provider ids, in 'complete' priority order
---@field per_filetype? table<string, zcmp.SourceList> Overrides `default` for these filetypes
---@field providers? table<string, zcmp.Provider>

---Provider ids. `inherit_defaults` puts `sources.default` in front of them.
---@class zcmp.SourceList
---@field [integer] string
---@field inherit_defaults? boolean

---What a provider contributes to 'complete'. `flags` are literal option flags;
---`module` is a Lua module serving matches. One of the two is required.
---@class zcmp.Provider
---@field name? string Shown by `:ZCmp status` and `:checkhealth zcmp`
---@field flags? string[] zcmp's own; literal 'complete' flags, e.g. `{ '.', 'w', 'b' }`
---@field module? string Module exposing `source()` or `completefunc()`; see |zcmp-providers|
---@field opts? table Passed verbatim to the module's `enable()` and `source()`; for the built-in `lsp` provider, exactly `autotrigger` also reaches |vim.lsp.completion.enable()|, and only while `completion.menu.auto_show` is on -- `extend_trigger_characters` is zcmp's own trigger-character widening, and other `enable()` options (e.g. `convert`, `cmp`) are not passed through
---@field max_items? integer Cap, applied as 'complete's own `^{count}`
---@field enabled? boolean|fun(bufnr: integer): boolean The function form's answer is read as a boolean, nil included: nil is false, like every other falsy value
---@field available? fun(bufnr: integer): boolean Checked per buffer, once `enabled` has answered true. zcmp's own; blink.cmp's `enabled` takes the same shape, but it has nothing named `available`. Read as a boolean the same way: nil is false

---@class zcmp.CompletionConfig
---@field menu? { auto_show?: boolean, auto_show_delay_ms?: integer } `auto_show` opens the menu as you type, i.e. 'autocomplete' and the `lsp` provider's autotrigger (default true); `auto_show_delay_ms` is 'autocompletedelay' (default 200), which the autotrigger does not wait for
---@field documentation? { auto_show?: boolean } Documentation popup, i.e. `popup` in 'completeopt' (default true)
---@field list? zcmp.ListConfig

---@class zcmp.ListConfig
---@field max_items? integer Default cap for providers that set none
---@field selection? { preselect?: boolean, auto_insert?: boolean }

---Which engine holds a snippet once it is in the buffer. A preset rewrites
---the defaults of the other three fields -- and, for 'luasnip', which module
---the `snippets` provider points at -- so an explicit field still wins.
---`expand` is called by ZCmp's own snippet sources and offered to zsnip's;
---a server's snippet items go through vim.snippet regardless, which is why
---the 'luasnip' preset answers for both engines. See |zcmp-snippets|.
---@class zcmp.SnippetsConfig
---@field preset? "default"|"luasnip"
---@field expand? fun(body: string)
---@field active? fun(filter?: vim.snippet.ActiveFilter): boolean
---@field jump? fun(direction: -1|1)

---|zcmp.Config| once `setup()` has merged it over the defaults: the same
---shape, with nothing left unset. What every module reads.
---@class zcmp.ResolvedConfig
---@field enabled fun(bufnr: integer): boolean
---@field keymap zcmp.KeymapConfig
---@field sources zcmp.ResolvedSources
---@field completion zcmp.ResolvedCompletion
---@field fuzzy { enabled: boolean }
---@field snippets zcmp.ResolvedSnippets
---@field signature { enabled: boolean }
---@field appearance { kind_hl: string|false }

---@class zcmp.ResolvedSources
---@field default string[]
---@field per_filetype table<string, zcmp.SourceList>
---@field providers table<string, zcmp.Provider>

---@class zcmp.ResolvedCompletion
---@field menu { auto_show: boolean, auto_show_delay_ms: integer }
---@field documentation { auto_show: boolean }
---@field list { max_items?: integer, selection: { preselect: boolean, auto_insert: boolean } }

---@class zcmp.ResolvedSnippets
---@field preset string
---@field expand fun(body: string)
---@field active fun(filter?: vim.snippet.ActiveFilter): boolean
---@field jump fun(direction: -1|1)

return {}
