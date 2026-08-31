---The keys ZCmp maps, and what pressing one runs.
---
---Every mapping is buffer-local, so a key ZCmp does not handle -- and every key
---in every buffer it does not attach to -- keeps whatever it was mapped to.
---See `zcmp.fallback` for the other half of that.

local api = vim.api
local commands = require('zcmp.api')
local config = require('zcmp.config')
local fallback = require('zcmp.fallback')

local M = {}

---Commands that make sense while a placeholder is selected, and so are mapped
---in Select mode as well as Insert -- blink.cmp's rule, and its list, less
---the two signature-scroll commands ZCmp has no equivalent of, plus
---`snippet_delete`, which is ZCmp's own. A function entry is mapped there
---too, as blink does: it is opaque and may well be one of these (the usual
---port is `if cmp.snippet_active() then return cmp.snippet_forward() end`).
---Mapping one there is safe because a function that answers false in Select
---mode falls through to `fallback`, whose Select-mode handling is Vim's own
---(see `fallback.run`): an smap's rhs runs, any other mapping runs from
---Visual, and with no mapping at all the key is fed natively -- which in
---Select mode types it over the selection, exactly as if ZCmp were not there.
local SELECT_MODE_COMMANDS = {
  snippet_forward = true,
  snippet_backward = true,
  snippet_delete = true,
  show_signature = true,
  hide_signature = true,
}

---Commands that run whatever the key is mapped to without ZCmp in the way,
---and so end the list: whatever follows one can never run.
local TERMINAL_COMMANDS = {
  fallback = true,
  fallback_to_mappings = true,
}

---What every preset but `none` carries -- blink.cmp's shared keys, plus
---`<CR>`, which is ZCmp's own addition. `fallback` alone runs exactly what
---Enter did before ZCmp attached, the displaced mapping or Vim's own newline,
---but through `fallback.feed()`, which closes a menu that has nothing
---selected ahead of the key. Without the entry the key never reaches the
---feeder, and in the menu |vim.lsp.completion| rebuilds -- built by
---|complete()|, with 'noinsert' and nothing selected -- Vim's own
---`compl_enter_selects` rule ends completion and inserts no newline: the first
---Enter over a server item closed the menu, the second opened the line.
local SHARED = {
  ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
  ['<CR>'] = { 'fallback' },
  ['<Up>'] = { 'select_prev', 'fallback' },
  ['<Down>'] = { 'select_next', 'fallback' },
  ['<C-p>'] = { 'select_prev', 'fallback' },
  ['<C-n>'] = { 'select_next', 'fallback' },
  ['<C-e>'] = { 'hide', 'fallback' },
  ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
  ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
  ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
  ['<C-y>'] = { 'select_and_accept', 'fallback' },
  ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
}

---@param keymap table<string, zcmp.Command[]>
---@return table<string, zcmp.Command[]>
local function preset(keymap)
  return vim.tbl_extend('force', SHARED, keymap)
end

---The four |zcmp.KeymapPreset|s, and all of them: a name that is not one is
---reported by `setup()` and the default used here, so this is a closed set at
---runtime as well as in the type. A keymap of your own is per-key entries over
---a preset.
---@type table<zcmp.KeymapPreset, table<string, zcmp.Command[]>>
local PRESETS = {
  none = {},
  default = preset({
    ['<Tab>'] = { 'snippet_forward', 'fallback' },
  }),
  ['super-tab'] = preset({
    ['<Tab>'] = { 'select_and_accept', 'snippet_forward', 'fallback' },
  }),
  enter = preset({
    ['<CR>'] = { 'accept', 'fallback' },
    ['<Tab>'] = { 'snippet_forward', 'fallback' },
  }),
}

---The names of |PRESETS|, sorted -- what `M.check()` checks `keymap.preset`
---against, and names in its report of an unknown one. Local: the report
---moved into `M.check()` below, and nothing outside this module reads it.
---@return string[]
local function presets()
  local names = vim.tbl_keys(PRESETS)
  table.sort(names)
  return names
end

---@type table<integer, { keys: { mode: string, lhs: string, callback: function }[], captured: table<string, table> }>
local installed = {}

---The user's own spellings, sorted -- so that two spellings of one key
---resolve the same way every session, rather than by hash order -- and
---deduped by `vim.keycode()`, since `<C-Space>` and `<C-space>` are one
---mapping to Vim. Shared by `M.check()` and `M.resolve()`, so the spelling
---the former reports as the winner is, by construction, the one the latter
---keeps: the last one standing after each `lhs` in sorted order overwrites
---`seen[key]` in turn.
---@param keymap table<string, unknown>
---@return { lhs: string, key: string, duplicate_of: string? }[]
local function by_key(keymap)
  local spellings = {}
  for lhs in pairs(keymap) do
    if lhs ~= 'preset' then
      spellings[#spellings + 1] = lhs
    end
  end
  table.sort(spellings)

  local seen = {}
  local result = {}
  for _, lhs in ipairs(spellings) do
    local key = vim.keycode(lhs)
    result[#result + 1] = { lhs = lhs, key = key, duplicate_of = seen[key] }
    seen[key] = lhs
  end
  return result
end

---Every static problem `resolve()` would otherwise have to warn about on the
---first buffer it reaches: an unknown `keymap.preset`, next to the same
---report for `snippets.preset` in config.lua; a command written after a
---terminal one, which can never run, and reads exactly like the command
---being broken; one key spelled twice among the user's own entries --
---`<C-Space>` and `<C-space>` are one mapping to Vim, and the second would
---silently win; and a name that is not one of |zcmp-commands|, whether a typo
---or one of the predicates, which answer a question rather than doing
---anything. Called once, from `config.setup()`, with the pruned user
---keymap table -- entries of its own, plus `preset` -- so it never depends on
---a buffer being attached at all.
---@param keymap table<string, zcmp.Command[]|false>|{ preset: string }
function M.check(keymap)
  if keymap.preset and not PRESETS[keymap.preset] then
    vim.notify(
      ('zcmp.setup: %q is not a keymap preset; ZCmp has %s.'):format(
        tostring(keymap.preset),
        config.list_join(vim.tbl_map(function(name)
          return ("'%s'"):format(name)
        end, presets()))
      ),
      vim.log.levels.WARN
    )
  end

  for _, spelling in ipairs(by_key(keymap)) do
    local lhs = spelling.lhs
    if spelling.duplicate_of then
      vim.notify(
        ('zcmp.setup: keymap spells one key twice, as %q and %q; using %q'):format(spelling.duplicate_of, lhs, lhs),
        vim.log.levels.WARN
      )
    end

    local entry = keymap[lhs]
    if type(entry) == 'table' then
      for index, command in ipairs(entry) do
        if type(command) == 'string' and not TERMINAL_COMMANDS[command] then
          if commands.predicates[command] then
            vim.notify(
              ('zcmp.setup: %s names %q, which answers a question rather than doing anything — it is not a keymap command'):format(
                lhs,
                command
              ),
              vim.log.levels.WARN
            )
          elseif type(commands[command]) ~= 'function' then
            vim.notify(('zcmp.setup: %s names %q, which is not a keymap command'):format(lhs, command), vim.log.levels.WARN)
          end
        end
        if TERMINAL_COMMANDS[command] and index < #entry then
          vim.notify(
            ('zcmp.setup: %s runs nothing after %q — it is the last command a list can hold'):format(lhs, command),
            vim.log.levels.WARN
          )
          break
        end
      end
    end
  end
end

---The preset with the user's own entries over it. An entry of `{}` is how a
---key is left alone. Silent: every static problem this merge could hit --
---an unknown preset, a key spelled twice, a command written after a terminal
---one -- was already said once by `M.check()`, from `config.setup()`.
---
---Keyed by the key, not its spelling: `<C-Space>` and `<C-space>`, `<tab>`
---and `<Tab>` are one mapping to Vim, and two entries for it would be mapped
---twice -- the second capturing the first as the mapping it displaced, and
---putting a live one of ZCmp's own back on |zcmp.disable()|. The spelling
---kept is the user's, which is the one they will look for in `:ZCmp status`.
---@return table<string, zcmp.Command[]>
function M.resolve()
  local keymap = config.options.keymap
  local name = keymap.preset or 'default'
  if not PRESETS[name] then
    name = 'default'
  end

  ---@type table<string, { lhs: string, entry: zcmp.Command[] }>
  local merged = {}
  local function put(lhs, entry)
    merged[vim.keycode(lhs)] = { lhs = lhs, entry = entry }
  end
  for lhs, entry in pairs(PRESETS[name]) do
    put(lhs, vim.deepcopy(entry))
  end
  -- Only the keys: config.lua's prune() has already dropped anything that
  -- was not a string key, `keymap = { 'super-tab' }` included.
  for _, spelling in ipairs(by_key(keymap)) do
    local entry = keymap[spelling.lhs]
    -- `false` disables the preset's own binding for this key -- blink's
    -- "same as {}".
    put(spelling.lhs, entry == false and {} or entry)
  end

  local resolved = {}
  for _, kept in pairs(merged) do
    resolved[kept.lhs] = kept.entry
  end
  return resolved
end

---@param entry zcmp.Command[]
---@return string[]
local function modes(entry)
  for _, command in ipairs(entry) do
    if type(command) == 'function' or SELECT_MODE_COMMANDS[command] then
      return { 'i', 's' }
    end
  end
  return { 'i' }
end

---A name resolves against |zcmp-commands| only. The predicates live in the
---same module and answer a question rather than doing anything, so binding one
---would swallow the key; naming one is the same mistake as a typo, and both
---were reported by `M.check()` at `setup()` -- here they resolve to nothing
---and the list moves on.
---@param command zcmp.Command
---@return function?
local function resolve_command(command)
  if type(command) == 'function' then
    return command
  end
  if commands.predicates[command] then
    return nil
  end
  -- `commands[command]` reaches `api.lua`'s whole function surface, which is
  -- the command namespace by that module's own declaration -- see its header.
  local fn = commands[command]
  return type(fn) == 'function' and fn or nil
end

---@param mode string
---@param lhs string
---@param entry zcmp.Command[]
---@param captured table<string, table>
local function run(mode, lhs, entry, captured)
  -- One batch for the whole list: a function entry that feeds and then falls
  -- through feeds twice from one press, and `fallback.batch` is what keeps
  -- those in call order.
  fallback.batch(function()
    for _, command in ipairs(entry) do
      if TERMINAL_COMMANDS[command] then
        -- Not under pcall like the branch below: see `fallback.run`.
        fallback.run(mode, lhs, captured[mode .. lhs])
        return
      end

      local fn = resolve_command(command)
      if fn then
        local ok, handled = pcall(fn, type(command) == 'function' and commands or nil)
        if not ok then
          vim.notify(('zcmp: the keymap entry for %s raised: %s'):format(lhs, handled), vim.log.levels.ERROR)
        elseif type(handled) == 'string' then
          -- blink's contract for a function entry, `fun(cmp): boolean | string
          -- | nil`: the string is keys in <Key> notation, fed as if typed --
          -- remapped, in front of the queue, the same as the key it stands in
          -- for -- and an empty one is the same as `false`.
          if handled ~= '' then
            fallback.press(handled, { remap = true, lhs = lhs })
            return
          end
        elseif handled then
          return
        end
      end
    end
  end)
end

---@param bufnr integer
function M.apply(bufnr)
  M.remove(bufnr)

  local state = { keys = {}, captured = {} }
  installed[bufnr] = state
  for lhs, entry in pairs(M.resolve()) do
    if #entry > 0 then
      for _, mode in ipairs(modes(entry)) do
        state.captured[mode .. lhs] = fallback.capture(bufnr, mode, lhs)
        local callback = function()
          run(mode, lhs, entry, state.captured)
        end
        local ok, err = pcall(vim.keymap.set, mode, lhs, callback, { buffer = bufnr, desc = 'zcmp' })
        if ok then
          state.keys[#state.keys + 1] = { mode = mode, lhs = lhs, callback = callback }
        else
          vim.notify_once(('zcmp: %s could not be mapped: %s'):format(lhs, err), vim.log.levels.ERROR)
        end
      end
    end
  end
end

---Take ZCmp's mappings back out, putting back whatever they displaced.
---
---A key can have been remapped again since |M.apply()| ran -- an `LspAttach`
---or a user's own `on_attach` landing on the same mode+lhs after zcmp's own
---mapping -- so the live mapping is only touched when it is still zcmp's.
---Anything else is left exactly as it is; the capture it would have restored
---is simply dropped.
---@param bufnr integer
function M.remove(bufnr)
  local state = installed[bufnr]
  installed[bufnr] = nil
  -- fallback owns a per-buffer mapping of its own; see `fallback.clear`. Run
  -- before the validity guard below -- its own pcall already tolerates a
  -- buffer that is gone, and skipping it for one left `plugged[bufnr]`
  -- behind for good.
  fallback.clear(bufnr)
  if not state or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  for _, key in ipairs(state.keys) do
    local live = fallback.capture(bufnr, key.mode, key.lhs)
    if live and live.callback == key.callback then
      pcall(vim.keymap.del, key.mode, key.lhs, { buffer = bufnr })
      local previous = state.captured[key.mode .. key.lhs]
      if previous then
        fallback.restore(bufnr, previous)
      end
    end
  end
end

---@param bufnr integer
---@return { mode: string, lhs: string }[]
function M.installed(bufnr)
  if not installed[bufnr] then
    return {}
  end
  local keys = {}
  for _, key in ipairs(installed[bufnr].keys) do
    keys[#keys + 1] = { mode = key.mode, lhs = key.lhs }
  end
  return keys
end

return M
