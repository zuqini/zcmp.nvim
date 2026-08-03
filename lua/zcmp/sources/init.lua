---Turns `sources.default` into a 'complete' value.
---
---Every source ZCmp offers is a 'complete' entry: core's own scanners are
---flags, a plugin's is a function entry, and the LSP is the omnifunc. The
---order of `sources.default` is the order of the option, which is the priority
---core time-slices by.

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

---The options `started` was filled against. |zcmp.setup()| replaces
---`config.options` wholesale rather than editing it, so a change of identity is
---exactly "these are different options now" -- and a module started from the
---previous set is holding `opts` that have since been replaced.
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
---@param start boolean Whether a module that has not run its enable() may
---@return string[] entries
---@return string? problem
local function entries(id, provider, start)
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

  -- Only on the way to writing 'complete'. Starting a provider is a lifecycle
  -- step, and `:ZCmp status` and `:checkhealth zcmp` reach this to report --
  -- a diagnostic that configures another plugin is the worst kind to read.
  if start and started[provider.module] == nil and type(module.enable) == 'function' then
    local ok_enable, err = pcall(module.enable, provider.opts)
    started[provider.module] = ok_enable or ('failed to start: %s'):format(err)
  end
  -- Remembered rather than retried: a module that would not start is not one
  -- to serve matches out of, and |zcmp.reload()| -- or another |zcmp.setup()| --
  -- is how you ask it again.
  if type(started[provider.module]) == 'string' then
    return resolved, ('module %q %s'):format(provider.module, started[provider.module])
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
  if provider.available and not provider.available(bufnr) then
    return { id = id, provider = provider, entries = {}, active = false, problem = M.UNAVAILABLE }
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
---asks for; a new set of options does the same by itself.
function M.reset()
  started = {}
end

return M
