---The LSP half of the engine.
---
---Both delivery paths are used, because each covers what the other misses: the
---`o` flag merges server items into the ranked menu but asks once per
---completion cycle, and |vim.lsp.completion| autotrigger re-asks per trigger
---character but delivers nothing for a plain keyword.

local M = {}

local WORD_CHARS = vim.split('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', '')

---Clients ZCmp has switched |vim.lsp.completion| on for, per buffer.
---|vim.lsp.completion| has no "is it on" to ask, and |zcmp.disable()| has to
---put back exactly what it took.
---@type table<integer, table<integer, true>>
local wired = {}

---`triggerCharacters` as the server declared them, per client id, or `false`
---where it declared none. The widened list lives on the client, so it outlives
---the buffer that widened it and is only put back once the last one goes.
---@type table<integer, string[]|false>
local declared = {}

---@param bufnr integer
---@return boolean
function M.available(bufnr)
  return next(vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/completion' })) ~= nil
end

---Widening the trigger list to every letter is what makes autotrigger re-ask
---on a plain keyword. Idempotent: a second call re-reads the widened list and
---dedups.
---@param client vim.lsp.Client
---@return string[]
function M.trigger_characters(client)
  local current = vim.tbl_get(client.server_capabilities, 'completionProvider', 'triggerCharacters') or {}
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
  local provider = client.server_capabilities.completionProvider
  if not provider or not client:supports_method('textDocument/completion') then
    return false
  end

  opts = opts or {}
  if opts.extend_trigger_characters ~= false then
    if declared[client.id] == nil then
      declared[client.id] = provider.triggerCharacters or false
    end
    provider.triggerCharacters = M.trigger_characters(client)
  end
  vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = opts.autotrigger ~= false })

  wired[bufnr] = wired[bufnr] or {}
  wired[bufnr][client.id] = true
  return true
end

---@param client_id integer
---@param bufnr integer
local function unwire(client_id, bufnr)
  -- The client is usually already gone by the time this runs -- that is what
  -- LspDetach means -- and enable(false) on a dead id is not worth raising for.
  pcall(vim.lsp.completion.enable, false, client_id, bufnr)

  local buffers = wired[bufnr]
  if buffers then
    buffers[client_id] = nil
    if next(buffers) == nil then
      wired[bufnr] = nil
    end
  end

  if declared[client_id] == nil then
    return
  end
  for _, ids in pairs(wired) do
    if ids[client_id] then
      return
    end
  end
  local client = vim.lsp.get_client_by_id(client_id)
  local provider = client and client.server_capabilities.completionProvider
  if provider then
    provider.triggerCharacters = declared[client_id] or nil
  end
  declared[client_id] = nil
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
    unwire(client_id, bufnr)
  end
  if not provider then
    return
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
---merged in -- there is nothing of ZCmp's own to announce.
---@param override? lsp.ClientCapabilities
---@return lsp.ClientCapabilities
function M.capabilities(override)
  return vim.tbl_deep_extend('force', vim.lsp.protocol.make_client_capabilities(), override or {})
end

return M
