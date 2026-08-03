---Machinery shared by the snippet source adapters.
---
---An adapter enumerates another plugin's snippets; everything a 'complete'
---source must then get right lives here, once: where the replaced run starts,
---matching it -- a `refresh = 'always'` source narrows its own list, core
---only narrows a list it was handed once -- and expanding what gets accepted.
---Modelled on zsnip.complete, which solved the same problems for its own
---registry.

local config = require('zcmp.config')

local M = {}

---@class zcmp.SnippetCandidate
---@field trigger string
---@field description? string Shown in the menu column
---@field info? string|fun(): string? Documentation; a function is resolved only for matched items
---@field body? string LSP snippet body, expanded through `snippets.expand`
---@field expand? fun() Expansion by reference, for a snippet that has no body. Wins over `body`

---What the last completefunc call offered, keyed by the id its items carry.
---A by-reference candidate cannot ride in `user_data` -- that round-trips
---through Vim -- so every item carries a key into this table instead. Ids
---never repeat, so an item surviving from an earlier call finds nothing
---rather than someone else's snippet.
---@type table<integer, zcmp.SnippetCandidate>
local offered = {}
local last_id = 0

local GROUP = 'zcmp.snippets'

---Where the run under the cursor starts, as `findstart` answers it: 0-based.
---The whole non-blank run, not the keyword -- triggers mix the two classes
---(`<div`, `console.log`), and stopping at the keyword boundary would leave
---the rest of what was typed in front of the expansion.
---@return integer
function M.findstart()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local start = vim.api.nvim_get_current_line():sub(1, col):find('%S+$')
  return (start or col + 1) - 1
end

---@param candidates zcmp.SnippetCandidate[]
---@param base string
---@param limit integer
---@return zcmp.SnippetCandidate[] matched
---@return string kept How much of `base` is not the trigger's
local function matching(candidates, base, limit)
  local by_trigger, triggers = {}, {}
  for _, candidate in ipairs(candidates) do
    if not by_trigger[candidate.trigger] then
      by_trigger[candidate.trigger] = candidate
      triggers[#triggers + 1] = candidate.trigger
    end
  end

  local function matched(prefix)
    if prefix == '' then
      return triggers
    end
    return vim.fn.matchfuzzy(triggers, prefix, { limit = limit })
  end

  local found, kept = matched(base), ''
  if #found == 0 then
    -- A trigger can be only the tail of the run: `req` typed as `(req` is the
    -- run, but the `(` belongs to the buffer. It is kept out of the match and
    -- put back into `word`, so accepting still replaces the whole run.
    local tail = base:match('()[%w_]+$')
    if tail and tail > 1 then
      found, kept = matched(base:sub(tail)), base:sub(1, tail - 1)
    end
  end

  local result = {}
  for _, trigger in ipairs(found) do
    if #result >= limit then
      break
    end
    result[#result + 1] = by_trigger[trigger]
  end
  return result, kept
end

---The completefunc answer for `base`, out of what the adapter enumerated.
---@param base string
---@param candidates zcmp.SnippetCandidate[]
---@param opts? { limit?: integer, documentation?: boolean }
---@return table
function M.complete(base, candidates, opts)
  opts = opts or {}
  local limit = opts.limit or 100
  local documented = opts.documentation ~= false

  offered = {}
  local matched, kept = matching(candidates, base, limit)

  local items = {}
  for _, candidate in ipairs(matched) do
    last_id = last_id + 1
    offered[last_id] = candidate

    local info = candidate.info
    if documented and type(info) == 'function' then
      local ok, resolved = pcall(info)
      info = ok and resolved or nil
    end

    items[#items + 1] = {
      -- `word` covers everything Vim replaces, so it carries `kept` back;
      -- `abbr` is what the menu shows, which is the trigger alone.
      word = kept .. candidate.trigger,
      abbr = candidate.trigger,
      kind = 'Snippet',
      menu = documented and candidate.description or '',
      info = documented and (type(info) == 'string' and info or candidate.body or '') or '',
      user_data = { zcmp_snip = { id = last_id, keep = #kept } },
    }
  end

  -- 'always' keeps the matching here. Without it Vim narrows the list it was
  -- handed by prefix as you type, quietly undoing the fuzzy match -- and the
  -- kept prefix -- that produced it.
  return { words = items, refresh = 'always' }
end

---Turn an accepted item back into its candidate and expand it. What the
---|CompleteDone| handler runs, taking the item as an argument because
---`v:completed_item` cannot be written by a test.
---@param completed table
function M.expand(completed)
  local data = vim.tbl_get(completed or {}, 'user_data', 'zcmp_snip')
  local candidate = type(data) == 'table' and offered[data.id] or nil
  offered = {}
  if not candidate then
    return
  end

  -- Vim inserted `word`: the trigger plus whatever `keep` bytes of the run
  -- were never the snippet's. The trigger is replaced; the rest stays.
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local start = col - #completed.word + (data.keep or 0)
  if start < 0 or start >= col then
    -- The range the trigger should occupy is not in the buffer, so something
    -- moved between the accept and here. Expanding anyway would put the body
    -- next to the trigger rather than over it.
    return
  end
  vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, col, {})

  if candidate.expand then
    candidate.expand()
  elseif type(candidate.body) == 'string' then
    config.options.snippets.expand(candidate.body)
  end
end

---Install the |CompleteDone| handler. Idempotent, and shared: however many
---adapters are enabled, one handler serves every `zcmp_snip` item.
function M.enable()
  vim.api.nvim_create_autocmd('CompleteDone', {
    group = vim.api.nvim_create_augroup(GROUP, { clear = true }),
    callback = function()
      M.expand(vim.v.completed_item)
    end,
  })
end

return M
