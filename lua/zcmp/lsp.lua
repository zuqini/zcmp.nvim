---The LSP half of the engine.
---
---Both delivery paths are used, because each covers what the other misses: the
---`o` flag merges server items into the ranked menu but asks once per
---completion cycle, and |vim.lsp.completion| autotrigger re-asks per trigger
---character but delivers nothing for a plain keyword.

local config = require('zcmp.config')

local M = {}

local WORD_CHARS = vim.split('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', '')

---@return table
local function options()
  return (config.options.sources.providers.lsp or {}).opts or {}
end

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
  local declared = vim.tbl_get(client.server_capabilities, 'completionProvider', 'triggerCharacters') or {}
  local seen, chars = {}, {}
  for _, char in ipairs(vim.list_extend(vim.list_extend({}, declared), WORD_CHARS)) do
    if not seen[char] then
      seen[char] = true
      chars[#chars + 1] = char
    end
  end
  return chars
end

---@param client vim.lsp.Client
---@param bufnr integer
---@return boolean attached
function M.attach(client, bufnr)
  local provider = client.server_capabilities.completionProvider
  if not provider or not client:supports_method('textDocument/completion') then
    return false
  end

  local opts = options()
  if opts.extend_trigger_characters ~= false then
    provider.triggerCharacters = M.trigger_characters(client)
  end
  vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = opts.autotrigger ~= false })
  return true
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
