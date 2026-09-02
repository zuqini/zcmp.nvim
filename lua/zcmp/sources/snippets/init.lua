---Machinery shared by the snippet source adapters.
---
---An adapter enumerates another plugin's snippets; everything a 'complete'
---source must then get right lives here, once: where the replaced run starts,
---matching it -- a `refresh = 'always'` source narrows its own list, core
---only narrows a list it was handed once -- and expanding what gets accepted.
---Modelled on zsnip.complete, which solved the same problems for its own
---registry.

local config = require('zcmp.config')
local sources = require('zcmp.sources')

local M = {}

---Nothing bounds an adapter's own enumeration; without a default this would
---match every snippet on the runtimepath against every keystroke.
local DEFAULT_LIMIT = 100

---@class zcmp.SnippetCandidate
---@field trigger string
---@field description? string Shown in the menu column
---@field info? string|fun(): string? Documentation; a function is resolved only for matched items
---@field body? string LSP snippet body, expanded through `snippets.expand`
---@field expand? fun() Expansion by reference, for a snippet that has no body. Wins over `body`

---What each adapter's latest `complete()` call offered, keyed by owner and
---then by the id its items carry. A by-reference candidate cannot ride in
---`user_data` -- that round-trips through Vim -- so every item carries a key
---into this table instead. Reset per owner at the top of that owner's own
---`complete()`: an adapter's on-screen items always come from its latest
---call, and the `vim.lsp.completion` restart that discards them carries
---those same ids, so a per-owner reset never invalidates a displayed one.
---Cleared entirely on a real accept and on |InsertLeave|, as the backstop.
---@type table<string, table<integer, zcmp.SnippetCandidate>>
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

---Normalises a field an adapter's own source may hand back as either a
---string or a table of lines -- `M.complete()` below applies the same
---string-or-nil contract to `trigger`, `description` and `body` once an
---adapter has produced candidates; this is the join an adapter itself needs
---while building one.
---@param value string|string[]|nil
---@param separator string
---@return string?
function M.joined(value, separator)
  if type(value) == 'table' then
    return table.concat(value, separator)
  end
  return type(value) == 'string' and value or nil
end

---Word is decided by byte, and every byte of a multibyte character counts:
---the same class `zcmp.sources.path` admits, for the same reason. A letter
---like `é` never opens a split, and a partial character never becomes a tail
---or a kept prefix.
local WORD_SET = '%w_\128-\255'
local WORD = '[' .. WORD_SET .. ']'
local NON_WORD = '[^' .. WORD_SET .. ']'
local INSIDE_WORD = '^' .. WORD .. WORD .. '$'

---@param candidates zcmp.SnippetCandidate[]
---@param run string
---@param limit integer
---@return zcmp.SnippetCandidate[] matched
---@return string kept How much of `run` is not the trigger's
local function matching(candidates, run, limit)
  local by_trigger, triggers, longest = {}, {}, 0
  for _, candidate in ipairs(candidates) do
    -- An adapter's own contract, enforced once here rather than by every
    -- adapter: a nil or non-string trigger would raise on the table-index
    -- assignment below, and an empty one matches nothing usefully.
    local trigger = candidate.trigger
    if type(trigger) == 'string' and trigger ~= '' and not by_trigger[trigger] then
      by_trigger[trigger] = candidate
      triggers[#triggers + 1] = trigger
      longest = math.max(longest, #trigger)
    end
  end

  local function matched(prefix)
    if prefix == '' then
      return triggers
    end
    return vim.fn.matchfuzzy(triggers, prefix, { limit = limit })
  end

  local function headed(tail)
    local head = tail:match('^' .. NON_WORD .. '+')
    local rest = tail:sub(#head + 1)
    local remainders, by_remainder = {}, {}
    for _, trigger in ipairs(triggers) do
      if vim.startswith(trigger, head) then
        local remainder = trigger:sub(#head + 1)
        remainders[#remainders + 1] = remainder
        by_remainder[remainder] = trigger
      end
    end
    local result = {}
    local hits = rest == '' and remainders or vim.fn.matchfuzzy(remainders, rest, { limit = limit })
    for _, remainder in ipairs(hits) do
      if #result >= limit then
        break
      end
      result[#result + 1] = by_remainder[remainder]
    end
    return result
  end

  local found, kept = matched(run), ''
  if #found == 0 then
    -- A trigger can be only the tail of the run: `req` typed as `(req` is the
    -- run, but the `(` belongs to the buffer. It is kept out of the match and
    -- put back into `word`, so accepting still replaces the whole run. Which
    -- tail is not the run's to decide: a trigger may contain the boundary
    -- character itself (`<div` in `x<di`), so every split next to a non-word
    -- character -- on either side of it, as the tail may start at one -- is
    -- tried against the candidates, longest tail first, and the first that
    -- matches wins: a trigger's own head is then never counted as kept.
    -- A tail that starts at the non-word character can only be a trigger's
    -- own head, so that head must match literally -- fuzzily, `(x` would
    -- find `fn(x`, which is not what `foo(x` typed -- and the rest is fuzzy
    -- like any other tail, so `<dv` finds `<div` at this boundary rather than
    -- `dv` finding it one byte later with the `<` counted as kept. One
    -- without a word character in it is nothing's head. A tail longer than
    -- the longest trigger matches neither way, so the search starts there --
    -- which is what bounds the cost per keystroke: one fuzzy match per
    -- boundary within the last `longest` bytes, the head-anchored one over
    -- only the triggers sharing that head.
    for i = math.max(2, #run - longest + 1), #run do
      if not run:sub(i - 1, i):match(INSIDE_WORD) then
        local tail = run:sub(i)
        local tails = {}
        if tail:match('^' .. WORD) then
          tails = matched(tail)
        elseif tail:find(WORD) then
          tails = headed(tail)
        end
        if #tails > 0 then
          found, kept = tails, run:sub(1, i - 1)
          break
        end
      end
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

---The completefunc answer for the run under the cursor, out of what the
---adapter enumerated.
---@param owner string The adapter's module name, and unique to it -- its own
---  slot in `offered` is reset here, so two adapters completing in the same
---  cycle never erase each other's ids, and two sharing an owner would.
---@param candidates zcmp.SnippetCandidate[]
---@param opts? { limit?: integer, documentation?: boolean }
---@return table
function M.complete(owner, candidates, opts)
  opts = opts or {}
  -- `owner` is passed to `sources.limit()` verbatim -- it is both the
  -- `offered` key and the report label, and only the dotted module name is
  -- unambiguous for a third-party adapter. A derived last-segment label
  -- collides across adapters sharing a leaf name (`notify_once` keys on the
  -- message) and misattributes a bad config to whichever module happens to
  -- share that leaf, including zcmp's own. Do not shorten it again.
  local limit = sources.limit(opts, DEFAULT_LIMIT, owner)
  local documented = opts.documentation ~= false
  offered[owner] = {}

  -- The run is read off the live line rather than taken from the completefunc's
  -- `base`: Vim fixes `base` at the first call of a cycle and hands the same
  -- one to every `refresh = 'always'` re-invocation, so matching on it would
  -- only ever see the first keystroke.
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local start = M.findstart()
  local run = vim.api.nvim_get_current_line():sub(start + 1, col)
  -- An empty run matches every trigger, which is right for a CTRL-N -- Vim's
  -- own sources list everything there too -- but 'autocomplete' asks again
  -- after every space typed, and that would open the whole list each time.
  -- Core's scanners offer nothing there, and so does zsnip.
  if run == '' and vim.o.autocomplete then
    return { words = {}, refresh = 'always' }
  end
  local matched, kept = matching(candidates, run, limit)

  local items = {}
  for _, candidate in ipairs(matched) do
    last_id = last_id + 1
    offered[owner][last_id] = candidate

    local info = candidate.info
    if documented and type(info) == 'function' then
      local ok, resolved = pcall(info)
      info = ok and resolved or nil
    end
    -- Same contract as `trigger` above, extended to the two fields an item
    -- carries into Vim untyped: a table `description` or `body` raises E730
    -- on every keystroke that reaches this source, not once.
    local description = type(candidate.description) == 'string' and candidate.description or nil
    local body = type(candidate.body) == 'string' and candidate.body or nil

    items[#items + 1] = {
      -- `word` covers everything Vim replaces, so it carries `kept` back;
      -- `abbr` is what the menu shows, which is the trigger alone.
      word = kept .. candidate.trigger,
      abbr = candidate.trigger,
      kind = 'Snippet',
      menu = (documented and description) or '',
      info = (documented and (type(info) == 'string' and info or body)) or '',
      -- `zcmp_start` is where `word` was built to replace from: what
      -- `sources.trim_head()` needs once vim.lsp.completion has re-inserted
      -- the item at the keyword boundary instead.
      user_data = { zcmp_start = start, zcmp_snip = { owner = owner, id = last_id, keep = #kept } },
    }
  end

  -- 'always' keeps the matching here. Without it Vim narrows the list it was
  -- handed by prefix as you type, quietly undoing the fuzzy match -- and the
  -- kept prefix -- that produced it.
  return { words = items, refresh = 'always' }
end

---Reports a raising snippet engine's error, attributed to it rather than to
---zcmp -- and to the trigger deletion the raise left behind, since the
---engine is expected to run at the cursor with the trigger already gone
---(see the call site) and there is no text left to put back.
---@param err string
local function report(err)
  vim.notify(
    ('zcmp: the snippet engine raised: %s (its trigger text was already removed)'):format(tostring(err)),
    vim.log.levels.ERROR
  )
end

---Reports a candidate that had nothing to expand it with: no function
---`expand` and no string `body`. Attributed to the adapter that offered it,
---not to the snippet engine, which was never reached -- and, as `report()`
---does, to the trigger deletion that already happened, since there is
---nothing left to put back either way.
---@param owner string
local function report_malformed(owner)
  vim.notify(
    ('zcmp: %s offered a snippet with neither expand() nor a string body (its trigger text was already removed)'):format(
      owner
    ),
    vim.log.levels.ERROR
  )
end

---Turn an accepted item back into its candidate and expand it. What the
---|CompleteDone| handler runs, taking the item as an argument because
---`v:completed_item` cannot be written by a test.
---@param completed table
function M.accept(completed)
  local data = vim.tbl_get(completed or {}, 'user_data', 'zcmp_snip')
  local owned = type(data) == 'table' and offered[data.owner] or nil
  local candidate = owned and owned[data.id] or nil
  if not candidate then
    -- Not a clear: vim.lsp.completion restarts the menu with vim.fn.complete()
    -- on an incomplete answer, which fires a `discard` while the items still
    -- carrying these ids are on screen and the owner is not asked again.
    return
  end
  offered = {}

  -- The head vim.lsp.completion may have left ahead of a relocated word is
  -- ZCmp's own CompleteDone handler's to trim, from another augroup -- so
  -- which of the two fires first is nothing to rely on. The trim is
  -- idempotent: after it, whether it ran there or here, the word is exactly
  -- what sits before the cursor, which is what the arithmetic below reads.
  sources.trim_head(completed)

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
  -- Deleted ahead of the expand, not after: the engine expands at the
  -- cursor and expects the trigger already gone. A raise below is reported
  -- rather than propagated -- see `report` -- but the deletion itself is not
  -- undone, so the message says so.
  vim.api.nvim_buf_set_text(0, row - 1, start, row - 1, col, {})

  local ok, err
  if type(candidate.expand) == 'function' then
    ok, err = pcall(candidate.expand)
  elseif type(candidate.body) == 'string' then
    ok, err = pcall(config.options.snippets.expand, candidate.body)
  else
    report_malformed(data.owner)
    return
  end
  if ok == false then
    report(err)
  end
end

---Install the |CompleteDone| handler. Idempotent, and shared: however many
---adapters are enabled, one handler serves every `zcmp_snip` item.
function M.enable()
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  vim.api.nvim_create_autocmd('CompleteDone', {
    group = group,
    callback = function()
      -- v:completed_item is set for any item selected when completion ended,
      -- including a discard (any non-completion key, <Esc>); expanding then
      -- would run the snippet on a completion the user just backed out of.
      if vim.v.event.reason == 'accept' then
        M.accept(vim.v.completed_item)
      end
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    callback = function()
      offered = {}
    end,
  })
end

return M
