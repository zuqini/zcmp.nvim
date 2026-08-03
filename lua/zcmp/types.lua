---Type declarations for ZCmp.nvim.
---
---Loaded for its annotations only; the module itself is empty.

---@class zcmp.Config
---@field enabled? fun(bufnr: integer): boolean Whether ZCmp drives completion in a buffer (default: `buftype` is empty)
---@field keymap? zcmp.KeymapConfig
---@field sources? zcmp.SourcesConfig
---@field completion? zcmp.CompletionConfig
---@field fuzzy? { enabled?: boolean } Fuzzy matching, i.e. `fuzzy` in 'completeopt' (default true)
---@field snippets? zcmp.SnippetsConfig
---@field signature? { enabled?: boolean } Whether |zcmp.show_signature()| does anything (default false)
---@field appearance? { kind_hl?: string|false } Highlight group the kind column borrows its colour from (default `'Special'`)

---Keys mapped in every buffer ZCmp attaches to, on top of a preset. Each
---value is a list of commands tried in order until one reports that it did
---something; `'fallback'` hands the key to whatever was mapped before, and
---always answers, so nothing written after it in a list can run.
---@class zcmp.KeymapConfig
---@field preset? zcmp.KeymapPreset
---@field [string] zcmp.Command[]

---@alias zcmp.KeymapPreset "default" | "super-tab" | "enter" | "none"

---A keymap entry: the name of a |zcmp-commands| function, or a function taking
---the ZCmp API and returning whether it handled the key.
---@alias zcmp.Command
---| string
---| fun(cmp: table): boolean?

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
---@field flags? string[] Literal 'complete' flags, e.g. `{ '.', 'w', 'b' }`
---@field module? string Module exposing `source()` or `completefunc()`; see |zcmp-providers|
---@field opts? table Passed verbatim to the module's `enable()` and `source()`
---@field max_items? integer Cap, applied as 'complete's own `^{count}`
---@field enabled? boolean|fun(bufnr: integer): boolean
---@field available? fun(bufnr: integer): boolean Checked per buffer, after `enabled`

---@class zcmp.CompletionConfig
---@field menu? { auto_show?: boolean } Open the menu as you type, i.e. 'autocomplete' (default true)
---@field documentation? { auto_show?: boolean } Documentation popup, i.e. `popup` in 'completeopt' (default true)
---@field list? zcmp.ListConfig
---@field trigger? { delay_ms?: integer } 'autocompletedelay' (default 200)

---@class zcmp.ListConfig
---@field max_items? integer Default cap for providers that set none
---@field selection? { preselect?: boolean, auto_insert?: boolean }

---How a snippet is stepped through once it is in the buffer. `active` and
---`jump` are what a different engine substitutes; `expand` and `preset` are
---blink.cmp's names, accepted so a config moves over unedited but never
---called -- whatever inserted the snippet expanded it. See |zcmp-snippets|.
---@class zcmp.SnippetsConfig
---@field preset? "default" Accepted and unused
---@field expand? fun(body: string) Accepted and unused
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
---@field menu { auto_show: boolean }
---@field documentation { auto_show: boolean }
---@field list { max_items?: integer, selection: { preselect: boolean, auto_insert: boolean } }
---@field trigger { delay_ms: integer }

---@class zcmp.ResolvedSnippets
---@field preset string
---@field expand fun(body: string)
---@field active fun(filter?: vim.snippet.ActiveFilter): boolean
---@field jump fun(direction: -1|1)

return {}
