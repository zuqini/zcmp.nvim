---Turns `sources.default` into a 'complete' value.
---
---Every source ZCmp offers is a 'complete' entry: core's own scanners are
---flags, and everything else -- a plugin's module, or the LSP's own -- is a
---function entry. The order of `sources.default` is the order of the option,
---which is the priority core time-slices by.

local config = require('zcmp.config')

local M = {}

---Why a provider contributes nothing *here*, rather than at all. Named because
---`:checkhealth zcmp` tells this apart from every other problem -- it is news
---about the buffer, not a fault to report -- and a reworded literal would
---silently reclassify it.
M.UNAVAILABLE = 'unavailable in this buffer'

---@class zcmp.ResolvedSource
---@field id string
---@field provider zcmp.Provider
---@field entries string[]
---@field active boolean
---@field problem? string Why it contributes nothing

---Modules whose `enable()` has run, keyed by module name: `true`, or why it
---would not start.
---@type table<string, true|string>
local started = {}

---The options `started` was filled against. `config.resolve()` -- reached by
---|zcmp.setup()| and both registration calls -- replaces `config.options`
---wholesale rather than editing it, so a change of identity is exactly "these
---are different options now" -- and a module started from the previous set is
---holding `opts` that have since been replaced.
---@type table?
local resolved_against = nil

---Watched here rather than reset from setup(), because this is the invariant:
---`started` belongs to one resolved config, and nowhere that replaces options
---can forget to say so.
local function forget_stale()
  if resolved_against ~= config.options then
    resolved_against = config.options
    started = {}
  end
end

---Which `setup()` option decided a buffer's id list, alongside the list
---itself -- `:checkhealth zcmp` names this rather than always blaming
---`sources.default` when the list is empty. An explicit, non-inheriting
---`per_filetype` entry replaces the list outright, so it alone is the answer;
---`inherit_defaults` only ever adds to `sources.default`, so an empty result
---there still traces back to `sources.default`, which is what a nil
---`filetype` means.
---@param bufnr integer
---@return string[] ids
---@return string? filetype
local function ids(bufnr)
  local sources = config.options.sources
  local ft = vim.bo[bufnr].filetype
  local per_filetype = sources.per_filetype[ft]
  if not per_filetype then
    return sources.default, nil
  end
  if not per_filetype.inherit_defaults then
    return per_filetype, ft
  end

  local merged = vim.list_extend({}, sources.default)
  for _, id in ipairs(per_filetype) do
    if not vim.tbl_contains(merged, id) then
      merged[#merged + 1] = id
    end
  end
  return merged, nil
end

---Runs `fn(bufnr)` with `bufnr` current, pcall-style, so a provider's
---`enabled`/`available` -- possibly a no-argument predicate reading
---`vim.bo`/`vim.b` un-indexed, blink.cmp's own form -- sees the buffer being
---decided rather than whichever one is current when this runs.
---@generic T
---@param bufnr integer
---@param fn fun(bufnr: integer): T
---@return boolean ok
---@return T|string result value fn returned, or the error it raised
local function in_buffer(bufnr, fn)
  return pcall(vim.api.nvim_buf_call, bufnr, function()
    return fn(bufnr)
  end)
end

---@param provider zcmp.Provider
---@param bufnr integer
---@return boolean
local function enabled(provider, bufnr)
  local predicate = provider.enabled
  if type(predicate) == 'function' then
    -- The predicate's answer is read as a boolean: nil is false, like every
    -- other falsy value, not "the field was left unset" (that reading is
    -- `predicate ~= false` below, for when there is no function at all).
    local ok, result = in_buffer(bufnr, predicate)
    if not ok then
      error(result, 0)
    end
    return result and true or false
  end
  return predicate ~= false
end

---Config checks a cap's type; its range -- a whole number `>= 1`, so not a
---float, zero, negative or infinite -- is the consumer's to check, because no
---shape table can say a range. A fraction rounds down with a warning;
---anything else warns and answers nil. `subject` names the offender in the
---report: `provider "buffer" max_items`, `path opts.limit`.
---@param value unknown
---@param subject string
---@return integer?
local function whole(value, subject)
  local wanted = type(value) == 'number' and value >= 1 and value < math.huge and math.floor(value) or nil
  if not wanted then
    vim.notify_once(
      ('zcmp: %s should be a whole number >= 1, not %s'):format(subject, vim.inspect(value)),
      vim.log.levels.WARN
    )
    return nil
  end
  if wanted ~= value then
    vim.notify_once(
      ('zcmp: %s should be a whole number, not %s'):format(subject, vim.inspect(value)),
      vim.log.levels.WARN
    )
  end
  return wanted
end

---A bad `max_items` would raise `E535` where it reaches 'complete', which
---detaches every buffer at once with one notification, so a rejected one is
---left off the entry. `subject` names the field the cap was read from, so
---an inherited `completion.list.max_items` is reported as itself, once,
---rather than as every provider it fell through to.
---@param cap? number
---@param subject string
---@return string
local function cap_suffix(cap, subject)
  if cap == nil then
    return ''
  end
  local wanted = whole(cap, subject)
  return wanted and ('^%d'):format(wanted) or ''
end

---Provider contract: a module that takes `opts.limit` -- path and the snippet
---adapters cap this way, before their items are built, unlike `max_items`'s
---`^{count}` after -- validates it here on the same terms as `max_items`, and
---a third-party module may too. `opts` is nowhere near a shape table
---(`config.lua` leaves third-party `opts` unshaped), so this is the only
---check the value gets.
---@param opts? { limit?: integer }
---@param default integer
---@param name string The module's own dotted name, e.g. `'zcmp.sources.path'`
---@return integer The limit, or `default` after reporting once
function M.limit(opts, default, name)
  local wanted = opts and opts.limit
  if wanted == nil then
    return default
  end
  return whole(wanted, name .. ' opts.limit') or default
end

---How many bytes of `pre`'s tail are `word`'s own head, typed exactly: the
---longest such head that has a non-keyword character in it, or 0.
---
---The guard is what makes reading the head off the text safe. The restart
---relocates an item to the `\k*$` boundary, so the head it skips always
---holds the last non-keyword character before the cursor; a head of keyword
---characters alone could not have been skipped, and a word that is all
---keyword characters -- every buffer word -- has none. `foo` accepted after
---`foo` is two words, not one relocated.
---@param word string
---@param pre string The line up to where the word landed
---@return integer
local function typed_head(word, pre)
  local boundary = vim.fn.match(word, '[^[:keyword:]]')
  if boundary < 0 then
    return 0
  end
  for n = math.min(#word - 1, #pre), boundary + 1, -1 do
    if pre:sub(-n) == word:sub(1, n) then
      return n
    end
  end
  return 0
end

---Put a completed item's run back at the column its source chose.
---
---Why: with a client attached, `vim.lsp.completion`'s `trigger()` rebuilds
---the menu through `vim.fn.complete()` at *one* column -- the server's start
---or the `\k*$` keyword boundary -- and carries every item already on screen
---across as it is. An item whose start is elsewhere is then re-inserted after
---its own head: accepting `console.log` typed as `console.l` gives
---`console.console.log`, and `./sub/alpha.txt` typed after `./sub/al` gives
---`./sub/./sub/alpha.txt`. This removes the bytes between the item's start
---and where the word actually landed, putting the run back as the source's
---own start column had it. ZCmp's own: |zcmp.enable()| installs one
---|CompleteDone| handler that calls this, in the `zcmp` augroup with every
---other autocmd |zcmp.disable()| gives back.
---
---Two ways to know the head. A module whose `findstart` is not the keyword
---boundary -- as the shipped snippet and path modules are not; their runs
---begin at `<div`'s `<` or a path token's `./` -- may record the absolute
---(0-based) column its item's `word` was built against as
---`user_data.zcmp_start`, and that key is authoritative: it also covers a
---head typed fuzzily (`cnsl.l` accepted as `console.log`). An item that
---records nothing -- the default provider, zsnip, which cannot name ZCmp,
---and any third-party F source -- is put back when the text before the word
---ends with the word's own head, on the terms `typed_head()` sets. That
---relocation can only come from `vim.lsp.completion`'s restart, so the text
---rule only applies where `vim.lsp.completion`'s restart can have run --
---`lsp.may_relocate()`'s question, not merely a client being attached, since
---one kept around for hover or diagnostics alone never restarts completion
---through zcmp. With that false, an F source whose `findstart` merely sits
---behind a byte that happens to match the word's head is left untouched.
---
---The server's own items are neither. The restart is what places them, at
---the column it restarts at, so they are never relocated -- and their words
---are not confined to keyword characters (`print(...)` with lua_ls's
---`callSnippet`, clangd's `->foo`), so the text rule would read the
---`print(` a user typed around one as a head to remove. They are left
---alone, told apart by the `user_data.nvim.lsp` mark `vim.lsp.completion`
---puts on each.
---
---A no-op when nothing was relocated -- the word sits at its start already --
---or when the word is not at the cursor at all, so it is safe on a discard
---and on a cancel that restored the original text, and idempotent: a second
---call finds the word at its start and leaves it.
---@param item? table The item, |v:completed_item| when not given
---@return integer removed How many bytes were taken out ahead of the word
function M.trim_head(item)
  item = item or vim.v.completed_item
  local word = item.word
  if type(word) ~= 'string' or word == '' then
    return 0
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local inserted = col - #word
  local line = vim.api.nvim_get_current_line()
  if inserted < 0 or line:sub(inserted + 1, col) ~= word then
    return 0
  end

  local start = vim.tbl_get(item, 'user_data', 'zcmp_start')
  if type(start) == 'number' then
    if start < 0 or inserted <= start then
      return 0
    end
  else
    if vim.tbl_get(item, 'user_data', 'nvim', 'lsp') then
      return 0
    end
    -- Reached directly rather than through buffer.lua: a read-only query,
    -- not the lifecycle traffic that module is the façade for. `wired` (one
    -- of the two routes `may_relocate()` checks) indexes by real buffer
    -- number, unlike the API's `0` shorthand.
    if not require('zcmp.lsp').may_relocate(vim.api.nvim_get_current_buf()) then
      return 0
    end
    local head = typed_head(word, line:sub(1, inserted))
    if head == 0 then
      return 0
    end
    start = inserted - head
  end
  vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, inserted, {})
  vim.api.nvim_win_set_cursor(0, { row, col - (inserted - start) })
  return inserted - start
end

---A flag can already carry its own count (`.^50`), and so can what a
---module's `source()` answers -- appending `suffix` to either produces
---`^50^100`, which 'complete' rejects with E535 and detaches the whole
---buffer. The entry's own count wins either way. `entry` must not be empty --
---a leading empty entry in 'complete' is the same E535 -- callers drop that
---case before ever reaching here.
---@param id string
---@param entry string
---@param suffix string
---@return string
local function capped(id, entry, suffix)
  if suffix ~= '' and entry:find('%^') then
    vim.notify_once(
      ('zcmp: provider %q entry %q already has its own count; max_items is ignored for it'):format(id, entry),
      vim.log.levels.WARN
    )
    return entry
  end
  return entry .. suffix
end

---`require`s `name` and, on the start path, runs its `enable(opts)` -- the
---single writer of `started[name]`, whether the failure is a load or an
---`enable()`. Remembers why it would not start and answers from that memo
---rather than retrying -- a module that would not start is not one to serve
---matches out of, and |zcmp.reload()| -- or another |zcmp.setup()|, or
---|zcmp.enable()| after |zcmp.disable()| -- is how you ask it again.
---`:ZCmp status` / `:checkhealth zcmp` reach this on
---demand, with `start = false`, so they can read a module's `source()`
---without either step; `resolve()` reaches it on every BufEnter and
---FileType with `start = true`, so only that path ever writes the memo.
---
---`require()` caches whatever the chunk returned, so a chunk that forgot
---`return M` -- or returned anything else that is not a table -- is cached
---forever unless something drops the entry. A query answers from whatever is
---cached and re-runs nothing -- dropping it there would make a diagnostic
---re-run a third party's chunk. The start path drops such a cached value
---before asking `require()`: it holds nothing worth keeping, and `reset()`
---has already cleared the memo by the time a fixed module is asked for
---again, so the first `reload()` after adding `return M` re-reads the file.
---@param name string
---@param opts table?
---@param start boolean
---@return table? module
---@return string? reason
local function load(name, opts, start)
  local memo = started[name]
  if type(memo) == 'string' then
    return nil, memo
  end

  if start and type(package.loaded[name]) ~= 'table' then
    package.loaded[name] = nil
  end

  local ok, module = pcall(require, name)
  if not ok then
    -- require() raises the same way on a miss and on a module that loaded
    -- and then errored; the loader's own miss is the only case that names
    -- the module "not found" in its message, so that is what tells them apart.
    -- A third case is the query path re-asking a module whose chunk already
    -- raised once: require() leaves its own sentinel in package.loaded, so a
    -- second call answers that, verbatim, rather than the original error --
    -- worth catching by itself, since the sentinel text names neither the
    -- module nor the actual fault. Only this module's own sentinel, and only
    -- off the start path: the start path dropped that entry just above, so a
    -- sentinel it meets is a dependency's, and the dependency's name in the
    -- raw error is the diagnosis.
    local err = tostring(module)
    local own_sentinel = "loop or previous error loading module '" .. name .. "'"
    local reason = not start and err:find(own_sentinel, 1, true)
        and 'failed to load earlier -- `:ZCmp reload` re-reads it'
      or err:find("module '" .. name .. "' not found", 1, true) and 'is not on the runtimepath'
      or ('failed to load: %s'):format(err)
    if start then
      started[name] = reason
    end
    return nil, reason
  end
  if type(module) ~= 'table' then
    local reason = 'is not a table -- did it return one?'
    if start then
      started[name] = reason
    end
    return nil, reason
  end

  if start and memo == nil and type(module.enable) == 'function' then
    local ok_enable, err = pcall(module.enable, opts)
    started[name] = ok_enable or ('failed to start: %s'):format(err)
  end
  local status = started[name]
  if type(status) == 'string' then
    return nil, status
  end

  return module, nil
end

---@param id string
---@param provider zcmp.Provider
---@param start boolean Whether a module that has not run its enable() may
---be started on this pass; see `load`.
---@return string[] entries
---@return string? problem
local function entries(id, provider, start)
  local cap, subject = provider.max_items, ('provider %q max_items'):format(id)
  if cap == nil then
    cap, subject = config.options.completion.list.max_items, 'completion.list.max_items'
  end
  local suffix = cap_suffix(cap, subject)

  local resolved = {}
  local flag_problem
  for _, flag in ipairs(provider.flags or {}) do
    if flag == '' then
      flag_problem = ('provider %q flags has an empty entry, dropped'):format(id)
    else
      resolved[#resolved + 1] = capped(id, flag, suffix)
    end
  end

  -- Every problem below is a module's; `flag_problem` is folded in ahead of
  -- it so a bad flag is not lost behind a module fault, and reported alone
  -- when the module is otherwise fine.
  ---@param reason string
  ---@return string[] entries
  ---@return string problem
  local function refuse(reason)
    local problem = reason
    if provider.module then
      problem = ('module %q %s'):format(provider.module, reason)
    end
    if flag_problem then
      problem = flag_problem .. '; ' .. problem
    end
    return resolved, problem
  end

  if not provider.module then
    if #resolved == 0 then
      -- `flag_problem` already names the provider once; naming it again here
      -- would repeat it, and "neither flags nor a module" would contradict
      -- `flag_problem` when the flags it names were just empty, not absent.
      local reason = flag_problem and 'declares no usable flags and no module'
        or ('provider %q declares neither flags nor a module'):format(id)
      return refuse(reason)
    end
    return resolved, flag_problem
  end

  local module, reason = load(provider.module, provider.opts, start)
  if not module then
    return refuse(reason or '')
  end

  -- source() takes precedence when a module has both: its answer *is* the
  -- entry, including nil, and completefunc() is used only when there is no
  -- source() at all.
  if type(module.source) == 'function' then
    local ok_source, result = pcall(module.source, provider.opts)
    if not ok_source then
      return refuse(('source() raised: %s'):format(tostring(result)))
    end
    if type(result) == 'string' and result ~= '' then
      resolved[#resolved + 1] = capped(id, result, suffix)
      return resolved, flag_problem
    end
    if result == '' then
      return refuse('serves no matches: source() answered an empty string')
    end
    return refuse(("source() answered %s, not a 'complete' entry"):format(vim.inspect(result)))
  end

  if type(module.completefunc) == 'function' then
    local entry = ("Fv:lua.require'%s'.completefunc"):format(provider.module)
    resolved[#resolved + 1] = capped(id, entry, suffix)
    return resolved, flag_problem
  end

  return refuse('serves no matches: it has neither source() nor completefunc()')
end

---@param id string
---@param provider zcmp.Provider?
---@param bufnr integer
---@param start boolean
---@return zcmp.ResolvedSource
local function one(id, provider, bufnr, start)
  if not provider then
    return { id = id, provider = {}, entries = {}, active = false, problem = 'no such provider' }
  end
  if not enabled(provider, bufnr) then
    return { id = id, provider = provider, entries = {}, active = false, problem = 'disabled' }
  end
  if provider.available then
    local ok, available = in_buffer(bufnr, provider.available)
    if not ok then
      error(available, 0)
    end
    if not available then
      return { id = id, provider = provider, entries = {}, active = false, problem = M.UNAVAILABLE }
    end
  end
  local found, problem = entries(id, provider, start)
  return { id = id, provider = provider, entries = found, active = #found > 0, problem = problem }
end

---@param bufnr integer
---@param start boolean
---@return zcmp.ResolvedSource[]
local function list(bufnr, start)
  forget_stale()
  local providers = config.options.sources.providers
  local seen, resolved = {}, {}

  for _, id in ipairs(ids(bufnr)) do
    if not seen[id] then
      seen[id] = true
      -- `enabled`, `available` and a third party's `source()` are all somebody
      -- else's code. One of them raising is that provider's problem to report,
      -- not something to take the rest of the list -- or `:checkhealth` -- down.
      local ok, source = pcall(one, id, providers[id], bufnr, start)
      resolved[#resolved + 1] = ok and source
        or { id = id, provider = providers[id] or {}, entries = {}, active = false, problem = tostring(source) }
    end
  end

  return resolved
end

---Every provider the buffer's source list names, in order, whether or not it
---contributes anything -- `:ZCmp status` and `:checkhealth zcmp` report on the
---ones that do not. Starts no provider module: reporting is a query.
---@param bufnr integer
---@return zcmp.ResolvedSource[]
function M.list(bufnr)
  return list(bufnr, false)
end

---A buffer's id list, and the filetype whose explicit, non-inheriting
---`per_filetype` entry produced it -- nil when `sources.default` did. For
---`:checkhealth zcmp` to name the right option when the list is empty.
---@param bufnr integer
---@return string[] ids
---@return string? filetype
function M.ids(bufnr)
  return ids(bufnr)
end

---The provider a buffer's source list names, or nil -- asked before the
---per-buffer availability check the list itself applies, so that the LSP
---wiring knows whether to touch a client at all, and with which `opts`.
---@param bufnr integer
---@param id string
---@return zcmp.Provider?
function M.provider(bufnr, id)
  local provider = config.options.sources.providers[id]
  if not provider or not vim.tbl_contains(ids(bufnr), id) then
    return nil
  end
  local ok, answer = pcall(enabled, provider, bufnr)
  return ok and answer and provider or nil
end

---The 'complete' value for a buffer, starting any provider module that the
---list names and nothing has started yet.
---@param bufnr integer
---@return string
function M.resolve(bufnr)
  local entry = {}
  for _, source in ipairs(list(bufnr, true)) do
    vim.list_extend(entry, source.entries)
  end
  return table.concat(entry, ',')
end

---Forget which provider modules have been started, so the next resolve enables
---them again -- with whatever `opts` are resolved by then. What |zcmp.reload()|
---asks for.
function M.reset()
  started = {}
end

return M
