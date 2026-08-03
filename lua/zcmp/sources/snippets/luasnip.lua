---LuaSnip as the snippet source -- what `snippets.preset = 'luasnip'` points
---the `snippets` provider at. A LuaSnip snippet is a program, not a body, so
---an accepted match expands by reference through `luasnip.snip_expand()`; the
---shared machinery deletes the inserted trigger first, exactly as it would
---for a body.
---
---Regex-trigger and hidden snippets are not offered: a regex is not a word to
---complete against, and hidden is the snippet asking not to be.

local core = require('zcmp.sources.snippets')

local M = {}

---@class zcmp.LuasnipOpts
---@field limit? integer Cap on items per response (default 100)
---@field documentation? boolean Attach docstring and description to the item (default true)
---@field show_condition? boolean Honour each snippet's `show_condition` (default true)

---@type zcmp.LuasnipOpts
local options = {}

---@param opts? zcmp.LuasnipOpts
function M.enable(opts)
  options = opts or {}
  if not pcall(require, 'luasnip') then
    error('luasnip is not on the runtimepath', 0)
  end
  core.enable()
end

---@param snip table
---@return string?
local function description(snip)
  local dscr = snip.dscr
  if type(dscr) == 'table' then
    return table.concat(dscr, ' ')
  end
  return type(dscr) == 'string' and dscr or snip.name
end

---Deferred: LuaSnip renders a docstring by evaluating the snippet's nodes,
---so it is only worth asking for the items that actually match.
---@param snip table
---@return fun(): string?
local function docstring(snip)
  return function()
    local ok, doc = pcall(snip.get_docstring, snip)
    if not ok then
      return nil
    end
    return type(doc) == 'table' and table.concat(doc, '\n') or doc
  end
end

---@param findstart 0|1
---@param base string
---@return integer|table
function M.completefunc(findstart, base)
  if findstart == 1 then
    return core.findstart()
  end
  local ok, luasnip = pcall(require, 'luasnip')
  if not ok then
    return { words = {} }
  end

  local col = vim.api.nvim_win_get_cursor(0)[2]
  local to_cursor = vim.api.nvim_get_current_line():sub(1, col)
  local filter = options.show_condition ~= false

  local candidates = {}
  for _, filetype in ipairs(luasnip.get_snippet_filetypes()) do
    for _, snip in ipairs(luasnip.get_snippets(filetype, { type = 'snippets' }) or {}) do
      local shown = not snip.hidden and not snip.regTrig
      if shown and filter and type(snip.show_condition) == 'function' then
        -- A condition that raises is that snippet's problem; showing it is
        -- the answer that loses nothing.
        local cond_ok, answer = pcall(snip.show_condition, to_cursor)
        shown = not cond_ok or answer ~= false
      end
      if shown then
        candidates[#candidates + 1] = {
          trigger = snip.trigger,
          description = description(snip),
          info = docstring(snip),
          expand = function()
            local ls = require('luasnip')
            -- The canonical copy: `snip` here is the table enumerated from,
            -- which LuaSnip does not expand in place.
            ls.snip_expand(ls.get_id_snippet(snip.id) or snip)
          end,
        }
      end
    end
  end
  return core.complete(base, candidates, options)
end

return M
