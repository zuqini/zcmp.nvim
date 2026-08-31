---What `'fallback'` in a keymap entry means: the key goes to whoever has it
---without ZCmp in the way -- a buffer-local mapping captured once, when ZCmp
---attached, but a global one looked up fresh on every press.
---
---That is the whole of ZCmp's relationship with other plugins that map insert
---mode. A `<CR>` belonging to an autopair plugin keeps working because this
---finds it and runs it, not because ZCmp knows the plugin exists.
---
---Also `M.batch()`, the feed queue that puts two feeds from one key press
---back in call order, and `M.menu_visible()`/`M.has_selection()`, the
---menu-state predicates `needs_menu_closed()` below and `api.lua` both ask --
---here because `api.lua` already requires this module and the reverse would
---cycle.

local api = vim.api

local M = {}

---Fed keys are not counted by |'maxmapdepth'|, so a result that contains its
---own key anywhere -- not only as a prefix -- would loop without bound if fed
---remapped: `['<CR>'] = function() return '<C-g>u<CR>' end` is the common
---undo-break idiom, and the `<CR>` is in the middle of the result. Fed
---non-remapped instead; `<Plug>` still resolves under noremap.
---@param keys string
---@param lhs? string A mapping's own key
---@return boolean
local function contains_own_key(keys, lhs)
  return lhs ~= nil and keys:find(vim.keycode(lhs), 1, true) ~= nil
end

local CR = vim.keycode('<CR>')
local CTRL_E = vim.keycode('<C-e>')

---What `feed` has queued since the outermost `M.batch()` opened, in the order
---it should run; nil outside a batch. `ends_completion` is what
---`needs_menu_closed` asks of each entry.
---@type { keys: string, flags: string, escape: boolean, ends_completion: boolean }[]?
local pending

---@param keys string
---@param flags string
---@param escape boolean
---@param ends_completion boolean
local function queue(keys, flags, escape, ends_completion)
  pending[#pending + 1] = { keys = keys, flags = flags, escape = escape, ends_completion = ends_completion }
end

---Run `fn` with every feed it makes collected, then feed them in reverse.
---Each is fed with the 'i' flag, in front of the queue, so two feeds from one
---key press land in the opposite order to the calls that made them: a
---function entry that calls `hide()` and then falls through to `fallback` on
---<CR> ran the <CR> first, and `hide()`'s <C-e>, arriving with no menu left
---to close, was |i_CTRL-E| and inserted the character from the line below.
---Flushed in reverse, the front-insertion puts them back in call order.
---`keymap.lua` opens one around a key's whole command list; `feed` opens one
---around its own pair when none is open, so a hand-called API function feeds
---at once. A batch inside a batch is a no-op; the outermost flushes, whether
---or not `fn` raised.
---@param fn fun()
function M.batch(fn)
  if pending then
    fn()
    return
  end
  pending = {}
  local ok, err = pcall(fn)
  local entries = pending
  pending = nil
  for i = #entries, 1, -1 do
    local entry = entries[i]
    api.nvim_feedkeys(entry.keys, entry.flags, entry.escape)
  end
  if not ok then
    error(err, 0)
  end
end

---Whether the completion menu is up. The one place this is asked from
---`vim.fn.pumvisible()` directly -- `api.lua`'s commands, and
---`needs_menu_closed` below, both ask it of this instead, so the menu-state
---question has one answer rather than two that can drift apart.
---@return boolean
function M.menu_visible()
  return vim.fn.pumvisible() == 1
end

---Whether the menu is up *and* something in it is selected -- the rule
---`<CR>`/`accept()` tell a selection apart from an open-but-empty menu by,
---and what `needs_menu_closed` below asks to tell a menu 'noinsert' left
---nothing selected in apart from one a source, or a prior `<C-n>`, marked.
---@return boolean
function M.has_selection()
  return M.menu_visible() and vim.fn.complete_info({ 'selected' }).selected ~= -1
end

---Vim's `compl_enter_selects` rule: in a menu vim.fn.complete() built with
---'noinsert' and nothing selected -- the LSP restart, after a server answers
----- <CR> ends completion without inserting a newline, while the same key in
---a menu 'autocomplete' opened is let through. Closing the menu ahead of a
---fed <CR> makes the two agree; <C-e> puts back nothing, since 'noinsert'
---inserted nothing. Only a leading <CR>: an autopair mapping's own answer
---begins with <C-e>/<C-y> and handles the menu itself. Asked about the keys
---that will actually run, by each route that knows them -- `feed` about its
---own, the `<script>` branch of `execute` about the value behind its
---`<Plug>`. And asked of the queue: each entry says whether it ends
---completion -- `hide()`'s <C-e>, an accept's <C-y> or <C-n><C-y>, the close
---queued here -- and once one is ahead of the <CR> there is no menu left for
---a second close, which would be |i_CTRL-E|. The entry says so itself rather
---than being read from its bytes: every command that ends completion feeds
---different keys, and a match on <C-e> missed `select_and_accept()`'s.
---@param keys string
---@return boolean
local function needs_menu_closed(keys)
  if not vim.startswith(keys, CR) or not M.menu_visible() or M.has_selection() then
    return false
  end
  for _, entry in ipairs(pending or {}) do
    if entry.ends_completion then
      return false
    end
  end
  return true
end

---@class zcmp.fallback.FeedOpts
---@field remap? boolean
---@field escape? boolean Ignored by `M.press`, which keycodes and so sets it itself
---@field lhs? string A mapping's own key
---@field runs? string What `keys` will run when they are a `<Plug>` standing in for it -- what the menu-close question is asked of; meaningless to `M.press`, whose `notation` is the keys themselves
---@field ends_completion? boolean Whether `keys` leave no menu behind -- `hide()`, an accept -- so a later <CR> in the batch needs no close

---The 'i' flag: these keys stand in for the one that was pressed, so they
---belong in front of the queue, not after whatever a macro or |feedkeys()|
---already queued. Queued through `M.batch`, so that a close for a leading
---<CR> -- its own flags, so a caller's remap never reaches it -- and the keys
---themselves land in that order.
---
---`escape` distinguishes two shapes of `keys`: `vim.keycode()`'d keys (a
---plain rhs, a `replace_keycodes` callback) have already turned any lone 0x80
---byte -- the last byte of many a multibyte character's UTF-8 encoding, and
---otherwise indistinguishable from K_SPECIAL -- into its 3-byte escape, so
---feeding them with `escape = true` would escape that sequence a second time
---and feed literal bytes instead of the key. Raw text -- a Vimscript `<expr>`
---mapping's expr-quote-escaped result, a non-`replace_keycodes` callback's
---return -- has not, so it needs `escape = true`: that is the same job
---`eval_map_expr()` does in Neovim's C source via `vim_strsave_escape_ks()`
---for exactly this shape of result, and `nvim_feedkeys()`'s third argument is
---the same routine.
---
---`opts.lhs` is the guard applied once for every caller: see `contains_own_key`.
---@param keys string
---@param opts? zcmp.fallback.FeedOpts
local function feed(keys, opts)
  opts = opts or {}
  local remap = opts.remap == true and not contains_own_key(keys, opts.lhs)
  M.batch(function()
    if needs_menu_closed(opts.runs or keys) then
      queue(CTRL_E, 'in', false, true)
    end
    queue(keys, remap and 'im' or 'in', opts.escape == true, opts.ends_completion == true)
  end)
end

---Feed a key in `<Key>` notation, standing in for the key that was pressed.
---The one feeder for that job: `keys` is keycoded here, so a caller never has
---to pair its own `vim.keycode()` with the right `escape` -- see `feed`'s
---docstring for what happens when that pairing is wrong. `opts.escape` is
---this function's own for that reason and is ignored if passed; `opts.runs`
---has no meaning here, since `notation` is the keys themselves.
---@param notation string
---@param opts? zcmp.fallback.FeedOpts
function M.press(notation, opts)
  feed(vim.keycode(notation), {
    remap = opts and opts.remap,
    lhs = opts and opts.lhs,
    ends_completion = opts and opts.ends_completion,
  })
end

---Reports a displaced mapping's error, naming the key rather than letting it
---propagate through zcmp's own frames as a traceback.
---
---`err` is whatever a `pcall` handed back -- a string from a raising rhs, but
---nil from a `vim.keymap.set` that returns nothing -- so it is stringified
---here rather than typed as one.
---@param lhs string
---@param err any A pcall's error value
local function report(lhs, err)
  vim.notify(('zcmp: the mapping for %s raised: %s'):format(lhs, (tostring(err):gsub('^Vim:', ''))), vim.log.levels.ERROR)
end

---The throwaway mapping a `<script>` mapping's rhs is fed through -- see
---`execute`'s `<script>` branch for why this is the one shape that needs it.
local PLUG_FALLBACK = '<Plug>(zcmp-fallback)'

---The key Vim itself puts behind a non-Select mapping's rhs to return to
---Select mode (|Select-mode-mapping|), as the raw bytes `M.run` feeds it as.
local K_SELECT = '\128\245X'

---The modes `execute()`'s `<script>` branch has actually created
---`PLUG_FALLBACK` in, per buffer -- so `M.clear()` deletes exactly those
---rather than guessing at every mode a keymap entry can be installed in.
---@type table<integer, table<string, true>>
local plugged = {}

---The shape of a |maparg()| dict decoded into |vim.keymap.set()| options --
---the shape is known here and nowhere else, so this is the one place that
---decodes it. Shared by `M.restore()` and `execute()`'s `<script>` branch: a
---`<script><expr>` mapping's `replace_keycodes` must survive into the
---throwaway `<Plug>` mapping the same way it survives a restore, or the
---mapping's real key bytes get escaped a second time.
---@param map table A |maparg()|-shaped dict
---@return table
local function set_opts(map)
  local expr = map.expr == 1
  local opts = {
    expr = expr,
    -- vim.keymap.set() ignores a `noremap` key and forces non-recursive
    -- unless `remap` says otherwise -- the inverse of maparg()'s own field.
    -- A `<script>` mapping's own `noremap` is 2, not 0 or 1, and is carried
    -- by `script` below rather than folded into `remap`.
    remap = map.noremap == 0,
    script = map.script == 1,
    nowait = map.nowait == 1,
    silent = map.silent == 1,
  }
  if expr then
    -- vim.keymap.set() defaults a missing `replace_keycodes` to `true` when
    -- `expr` is set, so an explicit `false` -- a `:map`-defined mapping
    -- always decodes to one or the other, never nil -- must be spelled out
    -- rather than left absent.
    opts.replace_keycodes = map.replace_keycodes == 1
  end
  return opts
end

---What Neovim's own eval_map_expr() does, step for step. maparg() hands
---back the rhs as typed (`m_orig_str`), but `:map` ran it through
---replace_termcodes() at definition time and evaluates that copy (`m_str`)
----- so bare notation in the source (`pumvisible() ? "<C-n>" : "<Tab>"`, no
---backslash) would otherwise reach nvim_eval() as literal text. vim.keycode()
---is the same call; it also escapes every lone 0x80 byte -- the tail of many
---a UTF-8 character -- which eval_map_expr() undoes with vim_unescape_ks()
---before evaluating, so the result carries raw bytes and real keys alike, and
---vim_strsave_escape_ks() -- `escape = true` at the feed -- can tell them
---apart: a K_SPECIAL followed by two bytes is a key, anything else is text.
---Without the unescape a literal `"x─y"` reaches eval already escaped and is
---escaped twice; without `escape` a value from a variable, never keycoded,
---loses its 0x80.
---@param rhs string
---@param lhs string
---@return string? The value, raw; nil when the expression raised, which has been reported
local function evaluate(rhs, lhs)
  local source = vim.keycode(rhs):gsub('\128\254X', '\128')
  local ok, evaluated = pcall(api.nvim_eval, source)
  if not ok then
    -- Natively the key would raise E117 and the rest; see execute()'s own
    -- docstring for why this is reported rather than swallowed.
    report(lhs, evaluated)
    return nil
  end
  -- eval_to_string() stringifies a Number result rather than discarding it:
  -- `inoremap <expr> <C-j> 42` inserts '42' natively.
  if type(evaluated) == 'string' then
    return evaluated
  elseif type(evaluated) == 'number' then
    return tostring(evaluated)
  end
  return ''
end

---Every branch below runs under pcall: this executes another plugin's
---captured mapping, and a traceback out of it would carry zcmp's own frames
---instead of naming the key that raised it. See `report`.
---@param map table A |maparg()|-shaped dict
---@param lhs string
---@param mode string
---@param bufnr integer
local function execute(map, lhs, mode, bufnr)
  -- A `<script>` mapping only remaps its own script-local (`<SID>`-prefixed)
  -- mappings within the rhs -- everything else is noremap. That is a property
  -- of the mapping being run, not of how the key that runs it was fed, and
  -- `nvim_feedkeys()` has no equivalent flag: `contains_own_key` below already
  -- forces this shape's own rhs (`<CR><SNR>N_...`, an endwise-style
  -- `imap <script> <CR> <CR><SID>...`) non-remapped, which would otherwise
  -- feed the resolved `<SNR>N_...` name back as literal text instead of
  -- running it. A throwaway buffer-local `<Plug>` mapping carrying the rhs
  -- with `script = true` gets Vim's own resolution: fed non-remapped, it
  -- still remaps only the script-local mapping inside it, exactly as typing
  -- the original key would. Not a route for an ordinarily-remapped mapping:
  -- there, a `<Plug>` rhs containing the displaced key would be remapped
  -- into zcmp's own mapping -- the skip Vim applies to a mapping whose own
  -- rhs begins with its own lhs protects the *original* mapping from that,
  -- and is lost once the rhs runs behind a `<Plug>` indirection with a
  -- different lhs of its own. Script-remap has no such gap to begin with:
  -- it remaps nothing but `<SNR>`-prefixed names anywhere in the rhs, leading
  -- or not, so the displaced key reappearing in it is never a loop. What
  -- `feed` asks of its own keys is asked here of what runs behind the
  -- `<Plug>`, since the `<Plug>` bytes it presses never begin with <CR> and
  -- so never close the menu themselves -- for a `<script><expr>` rhs, its
  -- value: evaluated here, the way the `<expr>` branch below evaluates, and
  -- handed back from a constant callback rather than written as a plain rhs.
  -- A plain rhs goes through replace_termcodes() when the mapping is
  -- defined, which turns the K_SPECIAL of every real key in a
  -- `replace_keycodes = 0` value -- what legacy `:map <script> <expr>`
  -- answers -- into literal text (`"xy\<BS>z"` inserted `xy<80>kbz`); an
  -- expr mapping's value is treated by Vim exactly as the original's would
  -- have been, `replace_keycodes` and all.
  if map.script == 1 and not map.callback then
    local rhs = map.rhs or ''
    ---@type string|function
    local target = rhs
    local runs = vim.keycode(rhs)
    if map.expr == 1 then
      local value = evaluate(rhs, lhs)
      if not value then
        return
      end
      target = function()
        return value
      end
      runs = map.replace_keycodes == 1 and vim.keycode(value) or value
    end
    local opts = set_opts(map)
    opts.buffer = bufnr
    local ok, err = pcall(vim.keymap.set, mode, PLUG_FALLBACK, target, opts)
    if not ok then
      report(lhs, err)
      return
    end
    plugged[bufnr] = plugged[bufnr] or {}
    plugged[bufnr][mode] = true
    feed(vim.keycode(PLUG_FALLBACK), { runs = runs })
    return
  end

  local keys, remap, escape
  if map.callback then
    if map.expr ~= 1 then
      local ok, err = pcall(map.callback)
      if not ok then
        report(lhs, err)
      end
      return
    end
    local ok, result = pcall(map.callback)
    if not ok then
      report(lhs, result)
      return
    end
    if type(result) ~= 'string' then
      return
    end
    if map.replace_keycodes == 1 then
      keys, escape = vim.keycode(result), false
    else
      keys, escape = result, true
    end
  elseif map.expr == 1 then
    -- See `evaluate`. This ignores `replace_keycodes` on purpose: a string
    -- rhs set through `vim.keymap.set(..., { expr = true })` carries
    -- `replace_keycodes = 1` too, but Neovim mishandles that combination
    -- today -- `"ab\<Left>c"` inserts the literal text `ab<80>klc` rather
    -- than moving the cursor -- so there is no working behaviour here to
    -- match.
    keys, escape = evaluate(map.rhs or '', lhs) or '', true
  else
    keys, escape = vim.keycode(map.rhs or ''), false
  end

  remap = map.noremap ~= 1
  -- See `contains_own_key`: a rhs that contains its own key would otherwise
  -- come straight back here.
  feed(keys, { remap = remap, escape = escape, lhs = lhs })
end

---A key with a modifier is stored in its own encoding, with the plain byte
---kept alongside as `lhsrawalt` -- `<C-j>` is `<80><fc>\4J` and `\n`. Either
---may be the one that matches.
---@param maps table[]
---@param lhs string
---@return table?
local function find(maps, lhs)
  local keys = vim.keycode(lhs)
  for _, map in ipairs(maps) do
    if map.lhsraw == keys or map.lhsrawalt == keys or (not map.lhsraw and vim.keycode(map.lhs) == keys) then
      return map
    end
  end
  return nil
end

---The buffer-local mapping a key already has, so that installing ZCmp's over
---it is reversible and `'fallback'` can still reach it.
---@param bufnr integer
---@param mode string
---@param lhs string
---@return table?
function M.capture(bufnr, mode, lhs)
  return find(api.nvim_buf_get_keymap(bufnr, mode), lhs)
end

---Put a mapping |M.capture()| found back exactly as it was.
---@param bufnr integer
---@param map table A |maparg()|-shaped dict, as |M.capture()| returns it
function M.restore(bufnr, map)
  -- nvim_buf_get_keymap()'s `mode` is the mapping's own mode, which need not
  -- match the mode it was captured under: `nvim_buf_get_keymap(bufnr, 's')`
  -- can answer a mode='v' entry, and restoring an smap's rhs under 's' types
  -- it as text instead of running it as a Visual-mode command.
  -- A mask left by `:map` plus an `*unmap` comes back as several letters
  -- ('nv'), which is a list of modes to vim.keymap.set(), not one.
  ---@type string|string[]
  local mode = map.mode == ' ' and '' or map.mode
  if #mode > 1 then
    mode = vim.split(map.mode, '')
  end
  local opts = set_opts(map)
  opts.buffer = bufnr
  opts.desc = map.desc
  pcall(vim.keymap.set, mode, map.lhs, map.callback or map.rhs or '', opts)
end

---Takes back the buffer-local `<Plug>` mapping `execute()`'s `<script>`
---branch may have left -- harmless to call when none was ever created. Called
---from `keymap.remove()` unconditionally, because the mapping `execute()`
---captures is as often global (an autopair plugin's) as buffer-local, and a
---global one leaves nothing in `state.captured` for `M.restore()` to key off.
---@param bufnr integer
function M.clear(bufnr)
  local modes = plugged[bufnr]
  if not modes then
    return
  end
  -- Per mode, each under its own pcall: a buffer that was `:bdelete`d out
  -- from under a mode's mapping would otherwise raise on `vim.keymap.del()`
  -- before the rest are tried.
  for mode in pairs(modes) do
    pcall(vim.keymap.del, mode, PLUG_FALLBACK, { buffer = bufnr })
  end
  plugged[bufnr] = nil
end

---`M.run` never raises: every error out of a displaced mapping is reported by
---key (see `report`) rather than propagating, which is why `keymap.lua`'s
---call site needs no pcall of its own.
---@param mode string
---@param lhs string
---@param captured? table The dict |zcmp.fallback.capture()| returned
function M.run(mode, lhs, captured)
  local map = captured or find(api.nvim_get_keymap(mode), lhs)
  if not map then
    M.press(lhs)
    return
  end
  -- Vim's own rule for Select mode (|Select-mode-mapping|): an smap's rhs
  -- runs in Select mode, where typed keys replace the selection, but any
  -- other mapping the key resolves to -- a vmap, a :map -- runs from Visual
  -- on the same selection, and Select mode is restored once it has run.
  -- <C-g> is that switch; after it the key is handed back for Vim to resolve
  -- itself (expr, buffer vs global), and ZCmp installs no x/v mapping for it
  -- to loop on. The restore is Vim's own K_SELECT, the key getchar.c appends
  -- behind such a rhs: it has no <Key> name, so it is fed as its raw
  -- special-key bytes -- K_SPECIAL, KS_SELECT, KE_FILLER, unchanged in
  -- decades -- appended after vim.keycode(), which would otherwise escape
  -- the K_SPECIAL byte into literal text. It has to be a single key: a rhs
  -- that reads a key itself (`getcharstr()`, a surround prompt) consumes
  -- exactly it and nothing else, as natively; the multi-key <Cmd> tail this
  -- once fed left its remainder to run as Normal-mode commands. `lhs` is
  -- omitted from the guard: '<C-g>' .. lhs contains lhs by construction, and the
  -- guard would otherwise feed <C-g> itself non-remapped -- defeating the
  -- point of the feed, which is letting Vim resolve the key's own mapping.
  if mode == 's' and map.mode ~= 's' then
    feed(vim.keycode('<C-g>' .. lhs) .. K_SELECT, { remap = true })
    return
  end
  execute(map, lhs, mode, api.nvim_get_current_buf())
end

return M
