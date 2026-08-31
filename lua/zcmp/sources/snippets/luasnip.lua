---LuaSnip as the snippet engine -- what `snippets.preset = 'luasnip'` points
---the `snippets` provider at, and the three session functions it rewrites
---`snippets.expand`, `snippets.active` and `snippets.jump` to. A LuaSnip
---snippet is a program, not a body, so an accepted match expands by reference
---through `luasnip.snip_expand()`; the shared machinery deletes the inserted
---trigger first, exactly as it would for a body.
---
---vim.lsp.completion expands a server's snippet items through vim.snippet
---regardless (see lsp.lua), so both engines can hold a live session: every
---session function asks LuaSnip first and falls through to vim.snippet.
---
---Regex-trigger and hidden snippets are not offered: a regex is not a word to
---complete against, and hidden is the snippet asking not to be.

local core = require('zcmp.sources.snippets')

-- The chunk's own module name, handed to it as `...` by `require` (Lua 5.1
-- manual §8.1) -- matches the string below without one going stale on rename.
local OWNER = ... or 'zcmp.sources.snippets.luasnip'

local M = {}

---@class zcmp.LuasnipOpts
---@field limit? integer Cap on items per response (default 100)
---@field documentation? boolean Attach docstring and description to the item (default true)
---@field show_condition? boolean Honour each snippet's `show_condition` (default true)

---@type zcmp.LuasnipOpts
local options = {}

---The preset wires the session functions whether or not LuaSnip is there
----- config is usable before setup(), and a lazily loaded LuaSnip can be
---absent at resolve time and present at the keypress -- so each asks at the
---time, and falls through to vim.snippet without it.
---@return table?
local function luasnip()
  local ok, ls = pcall(require, 'luasnip')
  return ok and ls or nil
end

---@param body string
function M.expand(body)
  local ls = luasnip()
  if ls then
    ls.lsp_expand(body)
  else
    vim.snippet.expand(body)
  end
end

---Whether LuaSnip has a placeholder to jump to from here. The local form:
---LuaSnip keeps a session until something ends it, so jumpable() stays true
---two hundred lines below the placeholder, and <Tab> would leave the
---fallback for a jump back into it. One predicate for active() and jump(),
---so that the two never disagree about whose session the jump goes to.
---@param direction -1|1
---@return boolean
local function held(direction)
  local ls = luasnip()
  return ls ~= nil and ls.locally_jumpable(direction) == true
end

---@param filter? vim.snippet.ActiveFilter
---@return boolean
function M.active(filter)
  if filter and filter.direction then
    return held(filter.direction) or vim.snippet.active(filter)
  end
  local ls = luasnip()
  return (ls ~= nil and ls.in_snippet() == true) or vim.snippet.active(filter)
end

---@param direction -1|1
function M.jump(direction)
  if held(direction) then
    luasnip().jump(direction)
  else
    vim.snippet.jump(direction)
  end
end

---@param opts? zcmp.LuasnipOpts
function M.enable(opts)
  options = opts or {}
  if not pcall(require, 'luasnip') then
    error('luasnip is not on the runtimepath', 0)
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

---LuaSnip does not constrain `dscr` or `name` to a string -- either may be a
---table of lines, and `name` has no fallback of its own, so it needs the
---same normalization `dscr` does.
---@param snip table
---@return string?
local function description(snip)
  return joined(snip.dscr, ' ') or joined(snip.name, ' ')
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
---@return integer|table
function M.completefunc(findstart)
  if findstart == 1 then
    return core.findstart()
  end
  local ls = luasnip()
  if not ls then
    return { words = {} }
  end

  local col = vim.api.nvim_win_get_cursor(0)[2]
  local to_cursor = vim.api.nvim_get_current_line():sub(1, col)
  local filter = options.show_condition ~= false

  local candidates = {}
  for _, filetype in ipairs(ls.get_snippet_filetypes()) do
    for _, snip in ipairs(ls.get_snippets(filetype, { type = 'snippets' }) or {}) do
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
            -- The canonical copy: `snip` here is the table enumerated from,
            -- which LuaSnip does not expand in place.
            ls.snip_expand(ls.get_id_snippet(snip.id) or snip)
          end,
        }
      end
    end
  end
  return core.complete(OWNER, candidates, options)
end

return M
