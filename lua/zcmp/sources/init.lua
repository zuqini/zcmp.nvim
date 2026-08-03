---Turns `sources.default` into a 'complete' value.
---
---Every source ZCmp offers is a 'complete' entry: core's own scanners are
---flags, a plugin's is a function entry, and the LSP is the omnifunc. The
---order of `sources.default` is the order of the option, which is the priority
---core time-slices by.

local config = require('zcmp.config')

local M = {}

---@class zcmp.ResolvedSource
---@field id string
---@field provider zcmp.Provider
---@field entries string[]
---@field active boolean
---@field problem? string Why it contributes nothing

---Modules whose `enable()` has run, keyed by module name.
---@type table<string, boolean>
local started = {}

---@param bufnr integer
---@return string[]
local function ids(bufnr)
  local sources = config.options.sources
  local per_filetype = sources.per_filetype[vim.bo[bufnr].filetype]
  if not per_filetype then
    return sources.default
  end
  if not per_filetype.inherit_defaults then
    return per_filetype
  end

  local merged = vim.list_extend({}, sources.default)
  for _, id in ipairs(per_filetype) do
    if not vim.tbl_contains(merged, id) then
      merged[#merged + 1] = id
    end
  end
  return merged
end

---@param provider zcmp.Provider
---@param bufnr integer
---@return boolean
local function enabled(provider, bufnr)
  if type(provider.enabled) == 'function' then
    return provider.enabled(bufnr) ~= false
  end
  return provider.enabled ~= false
end

---@param id string
---@param provider zcmp.Provider
---@return string[] entries
---@return string? problem
local function entries(id, provider)
  local cap = provider.max_items or config.options.completion.list.max_items
  local suffix = cap and ('^' .. cap) or ''

  local resolved = {}
  for _, flag in ipairs(provider.flags or {}) do
    resolved[#resolved + 1] = flag .. suffix
  end

  if not provider.module then
    if #resolved == 0 then
      return resolved, ('provider %q declares neither flags nor a module'):format(id)
    end
    return resolved
  end

  local ok, module = pcall(require, provider.module)
  if not ok then
    return resolved, ('module %q is not on the runtimepath'):format(provider.module)
  end

  if not started[provider.module] and type(module.enable) == 'function' then
    started[provider.module] = true
    module.enable(provider.opts)
  end

  local entry = type(module.source) == 'function' and module.source(provider.opts) or nil
  if not entry and type(module.completefunc) == 'function' then
    entry = ("Fv:lua.require'%s'.completefunc"):format(provider.module)
  end
  if type(entry) ~= 'string' then
    return resolved, ('module %q serves no matches: it has neither source() nor completefunc()'):format(provider.module)
  end

  resolved[#resolved + 1] = entry .. suffix
  return resolved, nil
end

---Every provider the buffer's source list names, in order, whether or not it
---contributes anything -- `:ZCmp status` and `:checkhealth zcmp` report on the
---ones that do not.
---@param bufnr integer
---@return zcmp.ResolvedSource[]
function M.list(bufnr)
  local providers = config.options.sources.providers
  local seen, resolved = {}, {}

  for _, id in ipairs(ids(bufnr)) do
    local provider = providers[id]
    if not seen[id] then
      seen[id] = true
      if not provider then
        resolved[#resolved + 1] =
          { id = id, provider = {}, entries = {}, active = false, problem = 'no such provider' }
      elseif not enabled(provider, bufnr) then
        resolved[#resolved + 1] = { id = id, provider = provider, entries = {}, active = false, problem = 'disabled' }
      elseif provider.available and not provider.available(bufnr) then
        resolved[#resolved + 1] =
          { id = id, provider = provider, entries = {}, active = false, problem = 'unavailable in this buffer' }
      else
        local found, problem = entries(id, provider)
        resolved[#resolved + 1] = {
          id = id,
          provider = provider,
          entries = found,
          active = #found > 0,
          problem = problem,
        }
      end
    end
  end

  return resolved
end

---Whether a buffer's source list names a provider at all -- asked before the
---per-buffer availability check the list itself applies, so that the LSP hook
---knows whether to wire a client up in the first place.
---@param bufnr integer
---@param id string
---@return boolean
function M.wants(bufnr, id)
  local provider = config.options.sources.providers[id]
  return provider ~= nil and vim.tbl_contains(ids(bufnr), id) and enabled(provider, bufnr)
end

---The 'complete' value for a buffer.
---@param bufnr integer
---@return string
function M.resolve(bufnr)
  local entry = {}
  for _, source in ipairs(M.list(bufnr)) do
    vim.list_extend(entry, source.entries)
  end
  return table.concat(entry, ',')
end

---Forget which provider modules have been started, so the next resolve enables
---them again. Used by |zcmp.reload()| and by tests.
function M.reset()
  started = {}
end

return M
