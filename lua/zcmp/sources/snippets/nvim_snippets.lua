---garymjr/nvim-snippets as the snippet source: point the `snippets`
---provider's `module` here. Its bodies are LSP snippet text, so an accepted
---match expands through `snippets.expand` -- vim.snippet by default, which is
---the same thing nvim-snippets expects of whatever completes for it.

local core = require('zcmp.sources.snippets')

-- The chunk's own module name, handed to it as `...` by `require` (Lua 5.1
-- manual §8.1) -- matches the string below without one going stale on rename.
local OWNER = ... or 'zcmp.sources.snippets.nvim_snippets'

local M = {}

---@class zcmp.NvimSnippetsOpts
---@field limit? integer Cap on items per response (default 100)
---@field documentation? boolean Attach body and description to the item (default true)

---@type zcmp.NvimSnippetsOpts
local options = {}

---@param opts? zcmp.NvimSnippetsOpts
function M.enable(opts)
  options = opts or {}
  if not pcall(require, 'snippets') then
    error('nvim-snippets is not on the runtimepath', 0)
  end
  core.enable()
end

---@param value string|string[]|nil
---@param separator string
---@return string?
local function joined(value, separator)
  if type(value) == 'table' then
    return table.concat(value, separator)
  end
  return type(value) == 'string' and value or nil
end

---@param findstart 0|1
---@return integer|table
function M.completefunc(findstart)
  if findstart == 1 then
    return core.findstart()
  end

  local ok, loaded = pcall(function()
    return require('snippets').load_snippets_for_ft(vim.bo.filetype)
  end)
  if not ok or type(loaded) ~= 'table' then
    return { words = {} }
  end

  local names = vim.tbl_keys(loaded)
  table.sort(names)

  local candidates = {}
  for _, name in ipairs(names) do
    local snippet = loaded[name]
    local body = joined(snippet.body, '\n')
    -- VSCode-format snippets may declare several prefixes; each is its own
    -- trigger for the same body.
    local prefixes = type(snippet.prefix) == 'table' and snippet.prefix or { snippet.prefix }
    for _, prefix in ipairs(prefixes) do
      if type(prefix) == 'string' and body then
        candidates[#candidates + 1] = {
          trigger = prefix,
          description = joined(snippet.description, ' '),
          body = body,
        }
      end
    end
  end
  return core.complete(OWNER, candidates, options)
end

return M
