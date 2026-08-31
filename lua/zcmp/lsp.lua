---The LSP half of the engine.
---
---Both delivery paths are used, because each covers what the other misses:
---|vim.lsp.omnifunc()| merges server items into the ranked menu but asks once
---per completion cycle, and |vim.lsp.completion| autotrigger re-asks per
---trigger character but delivers nothing for a plain keyword.

local config = require('zcmp.config')

local M = {}

local WORD_CHARS = vim.split('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', '')

---Clients ZCmp has switched |vim.lsp.completion| on for, per buffer.
---|vim.lsp.completion| has no "is it on" query, so |zcmp.disable()| switches
---every client of a buffer ZCmp drove back off -- whoever enabled it -- rather
---than restoring precisely what it took: the alternative is leaving a handle
---created under the server's own trigger list, which is the dead-autotrigger
---bug |M.sync()| exists to avoid.
---@type table<integer, table<integer, true>>
local wired = {}

---What a client's capabilities looked like before ZCmp touched them, per
---client id -- written once, on the first `M.attach()` call that actually
---changes something, so `original[id] ~= nil` is the whole answer to "did
---ZCmp touch this client". `provider` is `completionProvider` exactly as the
---server declared it -- a table if it declared one at all, `true` (off-spec,
---but tolerated) or `nil` under dynamic registration otherwise, which is also
---how `M.forget()` tells the two shapes of restore apart: a non-table
---`provider` means ZCmp substituted a table for it and the whole field goes
---back; a table one means only `trigger_characters` was ever changed.
---`trigger_characters` is `nil` unless ZCmp actually widened the list -- the
---widened one lives on the client's own table, so it outlives the buffer that
---widened it and is only put back once the last one goes.
---@type table<integer, { provider: any, trigger_characters: string[]? }>
local original = {}

---@param bufnr integer
---@return boolean
function M.available(bufnr)
  return next(vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/completion' })) ~= nil
end

---The 'complete' entry for the `lsp` provider: |vim.lsp.omnifunc()| called
---directly, rather than through 'omnifunc' -- a user's or another plugin's
---omnifunc left in that option must not stand in for it.
---@return string
function M.source()
  return 'Fv:lua.vim.lsp.omnifunc'
end

---Whether `vim.lsp.completion`'s restart can have relocated a completed
---item's start column on `bufnr` -- what `sources.trim_head()`'s
---text-derived branch needs before undoing anything. Three routes reach the
---restart and the predicate is their union: the wiring (`wired[bufnr]`),
---`M.source()`'s entry in 'complete', and a plain `o` flag over core's own
---LSP omnifunc. Route 3 tests the option's *value*, not just the flag, so a
---foreign omnifunc under `o` is not counted.
---
---Both errors corrupt text in opposite directions -- a false negative leaves
---a stale head (`console.console.log`), a false positive eats a typed byte
----- so do not narrow this to `wired` alone or widen it to `available()`
---alone. `M.available()` must stay ahead of every `vim.bo[bufnr]` read: it
---short-circuits for an invalid buffer, where `vim.bo` would raise.
---
---The full derivation, the measurements behind each route, and what is
---deliberately still false (a third party's own `enable()`) are in
---`.claude/review-decisions.md` § "`sources/init.lua` asks `lsp.lua` whether
---a relocation was possible, without going through `buffer.lua`".
---@param bufnr integer
---@return boolean
function M.may_relocate(bufnr)
  if next(wired[bufnr] or {}) ~= nil then
    return true
  end
  if not M.available(bufnr) then
    return false
  end
  local entry = M.source()
  -- Neovim's LSP attach handler writes 'omnifunc' in two shapes: the name
  -- `M.source()` already spells (0.12), and the function value itself
  -- (0.13+). Both reach the same `trigger()`, so both count -- matching only
  -- the string made this route dead on 0.13 and left the stale head
  -- (`console.console.log`) the route exists to prevent.
  local omnifunc = vim.bo[bufnr].omnifunc
  local lsp_omnifunc = omnifunc == entry:sub(2) or omnifunc == vim.lsp.omnifunc
  for _, element in ipairs(vim.split(vim.bo[bufnr].complete, ',', { plain = true })) do
    local base = element:match('^(.-)%^%d*$') or element
    if base == entry or (lsp_omnifunc and base == 'o') then
      return true
    end
  end
  return false
end

---Widening the trigger list to every letter is what makes autotrigger re-ask
---on a plain keyword. Idempotent: a second call re-reads the widened list and
---dedups.
---@param client vim.lsp.Client
---@return string[]
function M.trigger_characters(client)
  local declared_chars = vim.tbl_get(client.server_capabilities, 'completionProvider', 'triggerCharacters')
  -- A server answering `"triggerCharacters": null` decodes to `vim.NIL`, not
  -- `nil` -- `or {}` does not catch it, and list_extend() raises on it.
  local current = type(declared_chars) == 'table' and declared_chars or {}
  local seen, chars = {}, {}
  for _, char in ipairs(vim.list_extend(vim.list_extend({}, current), WORD_CHARS)) do
    if not seen[char] then
      seen[char] = true
      chars[#chars + 1] = char
    end
  end
  return chars
end

---@param client vim.lsp.Client
---@param bufnr integer
---@param opts? table The `lsp` provider's `opts`
---@return boolean attached
function M.attach(client, bufnr, opts)
  if not client:supports_method('textDocument/completion', bufnr) then
    return false
  end

  local id = client.id
  opts = opts or {}
  local widen = opts.extend_trigger_characters ~= false

  -- Widening needs somewhere to put the widened list. A server answering the
  -- off-spec `completionProvider: true` -- which |Client:supports_method()|
  -- tolerates -- has nothing to index, so an empty table is substituted for
  -- it and put back by `M.forget()`. An *absent* provider is left alone: it
  -- declared no trigger characters to widen from either way, and
  -- substituting there would make |Client:supports_method()| answer true for
  -- every buffer of the client -- it short-circuits on a truthy
  -- `completionProvider` before consulting a dynamic registration's
  -- `documentSelector` -- wiring buffers that registration excluded.
  -- Not widening writes nothing, so `completionProvider` is left exactly as
  -- declared; `vim.lsp.completion.enable()` tolerates any shape itself.
  -- Non-nil for an initialized client, which `supports_method()` established.
  local capabilities = client.server_capabilities --[[@as lsp.ServerCapabilities]]
  local declared_provider = capabilities.completionProvider
  widen = widen and (type(declared_provider) == 'table' or declared_provider == true)
  local substituting = widen and declared_provider == true
  local provider, declared_chars
  if widen then
    -- Branched on the type rather than on `substituting` so `provider` is a
    -- table on both paths -- the same condition, spelled where it narrows.
    if type(declared_provider) == 'table' then
      provider = declared_provider
    else
      provider = {}
      capabilities.completionProvider = provider
    end
    declared_chars = provider.triggerCharacters
    provider.triggerCharacters = M.trigger_characters(client)
  end

  -- The autotrigger opens the menu on its own, undelayed, on every widened
  -- trigger character -- so it answers to `completion.menu.auto_show` the
  -- same as 'autocomplete' does, not only to the provider's own opt. With
  -- only the provider consulted, `auto_show = false` switched 'autocomplete'
  -- off and the menu still opened as you typed, from the server alone.
  local autotrigger = opts.autotrigger ~= false and config.options.completion.menu.auto_show ~= false

  -- A client that stopped between get_clients() and this scheduled call is
  -- an invalid id vim.lsp.completion.enable() asserts on; the mutations
  -- above must not stick for a call that never wired anything -- including
  -- the `completionProvider` substitution just above, undone only when this
  -- call is the one that made it: another buffer may already be relying on
  -- it if this client is wired elsewhere.
  local ok = pcall(vim.lsp.completion.enable, true, id, bufnr, { autotrigger = autotrigger })
  if not ok then
    if widen then
      provider.triggerCharacters = declared_chars
      if substituting then
        capabilities.completionProvider = declared_provider
      end
    end
    return false
  end

  -- `original[id]` is written once: `substituting` implies `widen`, and a
  -- later call with `widen` true that finds it already set has nothing new
  -- to remember either.
  if original[id] == nil and widen then
    original[id] = { provider = declared_provider, trigger_characters = declared_chars }
  end
  wired[bufnr] = wired[bufnr] or {}
  wired[bufnr][id] = true
  return true
end

---Forget, synchronously, that a client was wired to a buffer -- everything
---`unwire()` does except switching |vim.lsp.completion| off, so the two
---cannot drift. `LspDetach` calls this before scheduling `M.sync()`: a
---buffer re-read (`:e`, `:e!`) fires `on_detach` and reattaches the same
---client id before that scheduled pass runs, so `wired[bufnr][client_id]`
---would otherwise still read true and `M.sync()` would treat the client as
---already wired -- doing neither the drop nor the re-`enable()` that
---recreates the handle under the widened trigger list. If this was the last
---buffer holding the client, `completionProvider` is put back to what the
---server declared -- whole, if ZCmp substituted a table for it, otherwise
---just `triggerCharacters` -- so a still-running client zcmp no longer
---drives on any buffer does not keep either.
---@param bufnr integer
---@param client_id integer
function M.forget(bufnr, client_id)
  local buffers = wired[bufnr]
  if buffers then
    buffers[client_id] = nil
    if next(buffers) == nil then
      wired[bufnr] = nil
    end
  end

  if original[client_id] == nil then
    return
  end
  for _, ids in pairs(wired) do
    if ids[client_id] then
      return
    end
  end
  local touched = original[client_id]
  original[client_id] = nil
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    return
  end
  if type(touched.provider) ~= 'table' then
    client.server_capabilities.completionProvider = touched.provider
  else
    local provider = client.server_capabilities.completionProvider
    if provider then
      provider.triggerCharacters = touched.trigger_characters
    end
  end
end

---@param bufnr integer
---@param client_id integer
local function unwire(bufnr, client_id)
  -- The client is usually already gone by the time this runs -- that is what
  -- LspDetach means -- and enable(false) on a dead id is not worth raising for.
  pcall(vim.lsp.completion.enable, false, client_id, bufnr)
  M.forget(bufnr, client_id)
end

---Bring a buffer's wiring in line with the clients it has now. `provider` is
---the `lsp` one when the buffer's source list names it; nil is how a buffer
---ZCmp has stopped driving -- or never drove -- is left with none.
---@param bufnr integer
---@param provider? zcmp.Provider
function M.sync(bufnr, provider)
  local clients = {}
  if provider then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/completion' })) do
      clients[client.id] = client
    end
  end

  local stale = {}
  for client_id in pairs(wired[bufnr] or {}) do
    if not clients[client_id] then
      stale[#stale + 1] = client_id
    end
  end
  for _, client_id in ipairs(stale) do
    unwire(bufnr, client_id)
  end
  if not provider then
    return
  end

  local unwired = false
  for client_id in pairs(clients) do
    if not (wired[bufnr] or {})[client_id] then
      unwired = true
      break
    end
  end
  if unwired then
    -- Neovim reads triggerCharacters and installs the autotrigger autocmds
    -- only on a buffer handle's first enable(); a synchronous LspAttach
    -- handler in the user's own config runs before this scheduled call and
    -- may have already created that handle with the server's own trigger
    -- list. Dropping every client for the buffer -- whoever enabled it --
    -- forces the handle to be recreated under ZCmp's widened list instead.
    -- Through unwire(), not an inlined enable(false), so original[id] is
    -- never left orphaned when the M.attach() below declines or fails.
    for client_id in pairs(clients) do
      unwire(bufnr, client_id)
    end
  end

  for client_id, client in pairs(clients) do
    if not (wired[bufnr] or {})[client_id] then
      M.attach(client, bufnr, provider.opts)
    end
  end
end

---@param bufnr integer
function M.detach(bufnr)
  M.sync(bufnr, nil)
end

function M.detach_all()
  for _, bufnr in ipairs(vim.tbl_keys(wired)) do
    M.detach(bufnr)
  end
end

---Capabilities to hand a language server. ZCmp completes through core, so
---these are |vim.lsp.protocol.make_client_capabilities()| with `override`
---merged in -- there is nothing of ZCmp's own to announce. `include_nvim_defaults
---= false`, blink.cmp's own second argument, skips that base entirely -- the
---result is `override` alone, deep-copied.
---@param override? lsp.ClientCapabilities
---@param include_nvim_defaults? boolean Default true
---@return lsp.ClientCapabilities
function M.capabilities(override, include_nvim_defaults)
  local base = include_nvim_defaults == false and {} or vim.lsp.protocol.make_client_capabilities()
  return vim.tbl_deep_extend('force', base, override or {})
end

return M
