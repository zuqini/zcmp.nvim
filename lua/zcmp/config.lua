---Resolved `setup()` options. Every default is usable on its own, so nothing
---in zcmp requires setup() to have run.

local M = {}

---@type zcmp.ResolvedConfig
local DEFAULTS = {
  enabled = function(bufnr)
    return vim.bo[bufnr].buftype == ''
  end,
  keymap = { preset = 'default' },
  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
    per_filetype = {},
    providers = {
      lsp = {
        name = 'LSP',
        -- vim.lsp.omnifunc, called directly rather than through 'omnifunc':
        -- that option can hold a user's or another plugin's own function
        -- instead, and this way it never has to.
        module = 'zcmp.lsp',
        available = function(bufnr)
          return require('zcmp.lsp').available(bufnr)
        end,
        opts = { autotrigger = true, extend_trigger_characters = true, retrigger = true },
      },
      path = {
        name = 'Path',
        module = 'zcmp.sources.path',
      },
      snippets = {
        name = 'Snippets',
        module = 'zsnip.complete',
        -- `complete` is the one key that is coordination rather than
        -- preference: buffer.lua is the single writer of 'complete', so zsnip
        -- must not append itself. How snippets are capped and documented is
        -- zsnip's setup() to say; how they are expanded is `snippets.expand`,
        -- resolved when a snippet is accepted rather than here, so a preset
        -- or an override set later still applies.
        opts = {
          complete = false,
          expand = function(body)
            M.options.snippets.expand(body)
          end,
        },
      },
      buffer = {
        name = 'Buffer',
        flags = { '.', 'w', 'b' },
        max_items = 100,
      },
    },
  },
  completion = {
    menu = { auto_show = true },
    documentation = { auto_show = true },
    list = { selection = { preselect = true, auto_insert = false } },
  },
  fuzzy = { enabled = true },
  snippets = {
    preset = 'default',
    expand = function(body)
      vim.snippet.expand(body)
    end,
    active = function(filter)
      return vim.snippet.active(filter)
    end,
    jump = function(direction)
      vim.snippet.jump(direction)
    end,
  },
  signature = { enabled = false },
  appearance = { kind_hl = 'Special' },
}

---What a snippets preset changes: the functions that drive a session, and the
---module the `snippets` provider points at. A preset rewrites the *defaults*,
---before the user's own options merge over them -- an explicit field beats
---its preset the same way it beats any other default. The functions live
---with the source they belong to; this is only the wiring, and it requires
---them lazily: the adapter loads the snippet core, which loads this module.
---@type table<string, fun(base: zcmp.ResolvedConfig)>
local PRESETS = {
  default = function() end,
  luasnip = function(base)
    base.snippets.expand = function(body)
      require('zcmp.sources.snippets.luasnip').expand(body)
    end
    base.snippets.active = function(filter)
      return require('zcmp.sources.snippets.luasnip').active(filter)
    end
    base.snippets.jump = function(direction)
      require('zcmp.sources.snippets.luasnip').jump(direction)
    end
    base.sources.providers.snippets = {
      name = 'Snippets',
      module = 'zcmp.sources.snippets.luasnip',
    }
  end,
}

local PROVIDER_SHAPE = {
  name = 'string',
  -- `__list` rather than a bare `table`, for the same reason `sources.default`
  -- is: `flags = { '.', want and 'w' or nil, 'b' }` with `want` false leaves a
  -- hole, and merging that by index over the default flags brought the
  -- switched-off flag back.
  flags = { __list = 'string' },
  module = 'string',
  opts = 'table',
  max_items = 'number',
  enabled = { 'boolean', 'function' },
  available = 'function',
}

---A provider's `opts` are opaque above: they belong to whatever module the
---provider names, and a third party's keys are not ours to check. The
---exception is a module zcmp ships whose `opts` keys are zcmp's own -- keyed
---on the module the provider reaches, setup()'s own `module` else the one on
---the `beneath()` layer `resolve()` stacks, rather than on the provider id:
---a user who points `providers.lsp.module` at their own module keeps their
---own keys opaque, and a `snippets.preset` that re-points the provider brings
---the adapter's shape with it. `zsnip.complete` is absent on purpose: its
---keys are not zcmp's, so the default snippets provider's `opts` stay opaque.
---`limit` is a `number` here and the contract's beyond that:
---`sources.limit()` says which numbers.
local OPTS_SHAPES = {
  ['zcmp.lsp'] = { autotrigger = 'boolean', extend_trigger_characters = 'boolean', retrigger = 'boolean' },
  ['zcmp.sources.path'] = { limit = 'number' },
  ['zcmp.sources.snippets.luasnip'] = { limit = 'number', documentation = 'boolean', show_condition = 'boolean' },
  ['zcmp.sources.snippets.nvim_snippets'] = { limit = 'number', documentation = 'boolean' },
}

---Mirrors DEFAULTS. A leaf is the accepted `type()`s; `__any` describes the
---value under keys the user names (a lhs, a filetype, a provider id);
---`__list` describes the value at a position, in a table addressed by
---position (`sources.default`, a `SourceList`) rather than by the keys it
---holds -- everything else naming keys of its own (`keymap`'s `preset`, a
---provider's fields) is a map. `__false` on a nested shape admits the
---literal `false` beside the table it describes (`keymap.__any` below),
---which is one flag rather than a second way to spell an alternatives
---list.
local SHAPES = {
  enabled = 'function',
  -- `false` is a keymap entry too -- blink's "same as {}", disabling a
  -- preset's own binding for that key -- so the shape admits the literal
  -- `false`; `true` has no shape here and is pruned and reported like any
  -- other wrong-typed value. The command list is `__list`-shaped for the same
  -- hole-idiom reason as a provider's `flags`: `{ 'accept', want and
  -- 'snippet_forward' or nil, 'fallback' }` with `want` false used to leave a
  -- hole `ipairs` never got past, silently swallowing the key.
  keymap = { preset = 'string', __any = { __list = { 'string', 'function' }, __false = true } },
  sources = {
    default = { __list = 'string' },
    per_filetype = { __any = { __list = 'string', inherit_defaults = 'boolean' } },
    providers = { __any = PROVIDER_SHAPE },
  },
  completion = {
    menu = { auto_show = 'boolean' },
    documentation = { auto_show = 'boolean' },
    list = {
      max_items = 'number',
      selection = { preselect = 'boolean', auto_insert = 'boolean' },
    },
  },
  fuzzy = { enabled = 'boolean' },
  snippets = { preset = 'string', expand = 'function', active = 'function', jump = 'function' },
  signature = { enabled = 'boolean' },
  -- The literal `false` disables the borrowed colour; `true` has no shape
  -- here and is pruned and reported at setup() like any other wrong-typed
  -- value, rather than being left for appearance.lua's own check.
  appearance = { kind_hl = { 'string', false } },
}

---@type zcmp.ResolvedConfig
M.options = vim.deepcopy(DEFAULTS)

---@param shape string|string[]|(string|boolean)[]
---@return (string|boolean)[]
local function alternatives(shape)
  return type(shape) == 'table' and shape or { shape }
end

---@param shape string|(string|boolean)[]
---@return string[] display names, with `false` spelled out
local function shape_names(shape)
  return vim.tbl_map(function(alt)
    if alt == false then
      return 'false'
    end
    return alt
  end, alternatives(shape))
end

---A shape alternative may be the literal `false` rather than a `type()`
---name -- `true` then fails the check like any other wrong-typed value,
---rather than being admitted as a `boolean` and re-checked downstream.
---@param shape string|(string|boolean)[]
---@param value any
---@return boolean
local function matches(shape, value)
  for _, alt in ipairs(alternatives(shape)) do
    if alt == false then
      if value == false then
        return true
      end
    elseif type(value) == alt then
      return true
    end
  end
  return false
end

---The shape to recurse into, or nil when `shape` is a leaf. A shape with no
---alternative at index 1 is a plain map of keys to shapes, and is itself
---that nested shape; anything else is an alternatives list of `type()`
---names, which has nothing to recurse into.
---@param shape string|(string|boolean)[]
---@return table?
local function nested_shape(shape)
  if type(shape) ~= 'table' or shape[1] ~= nil then
    return nil
  end
  return shape
end

---Re-indexes a `__list`-shaped table's numeric keys to `1..n` in ascending
---order; a key of its own (`inherit_defaults`) is left alone. Closes a hole
---left by the `cond and 'x' or nil` idiom, or by `prune()` just having
---dropped a wrong-typed element -- either way, the `ipairs` a source list is
---read back with must not stop partway through.
---@param list table
---@return table
local function compact(list)
  local numeric = {}
  local out = {}
  for key, value in pairs(list) do
    if type(key) == 'number' then
      numeric[#numeric + 1] = key
    else
      out[key] = value
    end
  end
  table.sort(numeric)
  for i, key in ipairs(numeric) do
    out[i] = list[key]
  end
  return out
end

---Options ZCmp used to take, keyed by the dotted path `prune()` builds, and
---what to say instead of `unknown option` -- which reads as a typo, the one
---thing a key that was documented and copied out of the README is not.
---@type table<string, string>
local REMOVED = {
  ['completion.menu.auto_show_delay_ms'] = "ZCmp now holds 'autocompletedelay' at 0. A non-zero delay let "
    .. 'vim.lsp.completion open the menu through vim.fn.complete() first, and a menu opened that way never '
    .. "asks a 'complete' source again for the rest of the completion cycle -- so every non-LSP source was "
    .. 'silently missing from it. Use `completion.menu.auto_show = false` to stop the menu opening as you '
    .. "type; core's own 'autocompletetimeout' is what bounds a slow source.",
}

---An unknown key is almost always a typo for a known one, and a merged-in
---`max_item` or `documention` is a silent no-op that reads exactly like the
---option not working. Reported rather than raised: a config that is wrong in
---one place should still get the rest -- which is also why the return value
---is `opts` with every unknown key, wrong-typed leaf and wrong-typed
---table-shaped option removed: an unknown key or a scalar of the wrong type
---must default exactly as a table does, rather than land in
---|zcmp.ResolvedConfig| as though it had been checked. A table that had
---entries and lost every one of them is removed with them, so it defaults
---too -- which is why a table-shaped input can come back absent.
---A `__list`-shaped table is compacted before it is returned -- a hole left
---by a dropped element, or by the `cond and 'x' or nil` idiom, must not stop
---the `ipairs` a source list, a provider's `flags` or a keymap entry's
---command list is read back with. This runs on every return, so a top-level
---call whose `shapes` is itself `__list`-shaped (`add_filetype_source`'s) is
---compacted the same as one nested inside a bigger `prune()`. A map
---(`keymap`, a provider's fields) has no positions to keep, so a key that is
---not a string there is reported and dropped before its value is even looked
---at, the same as a wrong-typed value would be.
---@param opts table
---@param shapes table
---@param path string
---@param where string The call being pruned, for the message
---@return table
local function prune(opts, shapes, path, where)
  local pruned = {}
  for key, value in pairs(opts) do
    local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
    if type(key) ~= 'string' and not shapes.__list then
      vim.notify(('%s: %s should be a key, got %s'):format(where, name, type(key)), vim.log.levels.WARN)
    else
      local shape = type(key) == 'number' and shapes.__list or shapes[key] or shapes.__any
      local nested = nested_shape(shape)
      if not shape then
        local removed = REMOVED[name]
        vim.notify(
          removed and ('%s: %s has been removed. %s'):format(where, name, removed)
            or ('%s: unknown option %q'):format(where, name),
          vim.log.levels.WARN
        )
      elseif nested then
        if value == false and nested.__false then
          -- `false` beside the table this shape describes: blink's "same as
          -- {}" for a keymap entry, kept as the literal it is.
          pruned[key] = value
        elseif type(value) ~= 'table' then
          vim.notify(
            ('%s: %s should be %s, got %s'):format(
              where,
              name,
              nested.__false and 'table or false' or 'a table',
              type(value)
            ),
            vim.log.levels.WARN
          )
        else
          local kept = prune(value, nested, name, where)
          -- `{}` handed in is an instruction -- empty this list -- but a table
          -- that had entries and lost every one of them to the check above has
          -- said nothing valid, and must default like any other wrong value.
          if next(value) == nil or next(kept) ~= nil then
            pruned[key] = kept
          end
        end
      elseif not matches(shape, value) then
        vim.notify(
          ('%s: %s should be %s, got %s'):format(where, name, table.concat(shape_names(shape), ' or '), type(value)),
          vim.log.levels.WARN
        )
      else
        pruned[key] = value
      end
    end
  end
  if shapes.__list then
    pruned = compact(pruned)
  end
  return pruned
end

---Re-prunes a provider's `opts` when `module` -- the one the provider
---reaches, which the caller answers since setup() and a registration answer
---it differently -- has an `OPTS_SHAPES` entry, so a typo in a key zcmp owns
---is reported like any other option rather than being silently the default.
---Runs after the main `prune()`, on its result, so the surviving `opts` is
---already known to be a table. An `opts` that had entries and lost every one
---of them is removed, on `prune()`'s own rule: it has said nothing valid, and
---must default rather than reach `merge()` as a `{}` that had been checked.
---@param id string
---@param provider table
---@param where string
---@param module string?
local function prune_shipped_opts(id, provider, where, module)
  local shape = module and OPTS_SHAPES[module]
  if not shape or type(provider.opts) ~= 'table' then
    return
  end
  local kept = prune(provider.opts, shape, 'sources.providers.' .. id .. '.opts', where)
  if next(kept) == nil and next(provider.opts) ~= nil then
    provider.opts = nil
  else
    provider.opts = kept
  end
end

---@param names string[]
---@return string
local function list_join(names)
  if #names <= 1 then
    return names[1] or ''
  end
  return table.concat(names, ', ', 1, #names - 1) .. ' and ' .. names[#names]
end

-- Exported so `keymap.check()` can name the keymap presets in the same voice
-- as this module's own report below, without a second copy of `list_join`.
M.list_join = list_join

---A snippets preset ZCmp does not know is not silently the default one; that
---reads exactly like the preset being broken. Said out loud instead, the way
---any engine plugs in without one. A `keymap.preset` gets the same report,
---from `keymap.check()` -- see `.claude/review-decisions.md`.
---@param pruned table
local function report_unknown_snippets_preset(pruned)
  local snippets = pruned.snippets
  if snippets and snippets.preset and not PRESETS[snippets.preset] then
    local names = vim.tbl_keys(PRESETS)
    table.sort(names)
    vim.notify(
      ('zcmp.setup: %q is not a snippets preset; ZCmp has %s. '):format(
        tostring(snippets.preset),
        list_join(vim.tbl_map(function(name)
          return ("'%s'"):format(name)
        end, names))
      ) .. 'Substitute another engine through snippets.expand, snippets.active and snippets.jump, '
        .. "and another source through the snippets provider's `module`.",
      vim.log.levels.WARN
    )
  end
end

---A `zcmp.SourceList` is a list carrying one key of its own,
---`inherit_defaults`, so `vim.islist` says no to it -- and merging one key by
---key merges the entries by *index*, leaving whatever was longer underneath.
---
---Anything else with both an array part and keys of its own is a provider's
---`opts`: free-form third-party data, a map, and merged as one.
---@param value table
---@return boolean
local function islist(value)
  return vim.islist(value) or (value.inherit_defaults ~= nil and vim.tbl_count(value) == #value + 1)
end

---Deep merge, except that a list replaces rather than extends: a
---`sources.default` of two entries means those two, not those two plus the
---four that were there.
---@param base any
---@param override any
---@return any
local function merge(base, override)
  if type(base) ~= 'table' then
    -- Nothing of ours under this key, so the user's own table is the value.
    -- Copied, because `options` outlives the table they handed setup() and
    -- |zcmp.add_filetype_source()| would otherwise edit it in place.
    return type(override) == 'table' and vim.deepcopy(override) or override
  end
  -- prune() has already pruned every wrong-typed value SHAPES describes;
  -- this is the backstop for a key SHAPES has no entry for -- a leaf shaped
  -- `table` (a provider's `opts`) is opaque below that point, so a value
  -- nested inside one can still disagree in shape with `base`.
  if type(override) ~= 'table' then
    return base
  end
  -- An empty table cannot be told from an empty map by its shape, so the base
  -- decides: emptying a list is an instruction, `{}` over a map is not.
  if islist(override) and (next(override) ~= nil or islist(base)) then
    return vim.deepcopy(override)
  end
  local merged = vim.deepcopy(base)
  for key, value in pairs(override) do
    merged[key] = merge(merged[key], value)
  end
  return merged
end

---Providers and per-filetype entries registered outside setup(). Kept because
---setup() replaces `options` wholesale: without them the call order would
---decide whether a registration survived, and a plugin registering one from
---its own config block runs before the user's setup() as often as after.
---@type { providers: table<string, zcmp.Provider>, per_filetype: table<string, zcmp.SourceList> }
local additions = { providers = {}, per_filetype = {} }

---@param per_filetype table<string, zcmp.SourceList>
---@param filetype string
---@param ids string[]
local function add_ids(per_filetype, filetype, ids)
  local list = per_filetype[filetype]
  if not list then
    list = { inherit_defaults = true }
    per_filetype[filetype] = list
  end
  for _, id in ipairs(ids) do
    if not vim.tbl_contains(list, id) then
      list[#list + 1] = id
    end
  end
end

---@param sources zcmp.ResolvedSources
local function apply_additions(sources)
  for id, provider in pairs(additions.providers) do
    -- A copy: `drop_repointed_opts()` edits this layer, and by reference that
    -- edit would outlive the setup() that called for it.
    sources.providers[id] = vim.deepcopy(provider)
  end
  for filetype, ids in pairs(additions.per_filetype) do
    add_ids(sources.per_filetype, filetype, ids)
  end
end

---The last table |M.setup()| pruned, kept so that a registration made
---afterwards can be resolved against it again -- see `resolve()`.
---@type table?
local configured = nil

---DEFAULTS with a snippets preset applied: the layer every registration
---sits on.
---@param preset? string
---@return zcmp.ResolvedConfig
local function base(preset)
  local resolved = vim.deepcopy(DEFAULTS)
  if preset and PRESETS[preset] then
    PRESETS[preset](resolved)
  end
  return resolved
end

---Everything under setup()'s own table: `base(preset)` with every
---registration applied. The one place those layers are stacked, read by
---`resolve()` and by setup()'s opts pruning alike, so which module an id
---reaches is never derived twice -- a second model of the stack read DEFAULTS
---only and missed a registration and the luasnip preset, both of which
---re-point an id before setup()'s own table lands.
---@param preset? string
---@return zcmp.ResolvedConfig
local function beneath(preset)
  local resolved = base(preset)
  apply_additions(resolved.sources)
  return resolved
end

---A `module` set in setup() that differs from the one underneath replaces
---what that layer carried for the old module: its `opts` are the old
---module's keys -- zsnip's coordination keys, say -- and a map-merge would
---otherwise hand them to a module that never asked for them, under the
---user's own. `opts` follow the module both ways: naming the shipped
---default's module again -- `module = 'zsnip.complete'` over the luasnip
---preset, which the default `expand` opt exists for -- brings the shipped
---default's `opts` back with it; any other module gets only the user's own.
---The id's own fields (`name`, `available`, `max_items`, `enabled`, `flags`)
---stay.
---@param providers table<string, zcmp.Provider>
local function drop_repointed_opts(providers)
  local overrides = configured and configured.sources and configured.sources.providers
  for id, override in pairs(overrides or {}) do
    local under = providers[id]
    if under and override.module and override.module ~= under.module then
      local shipped = DEFAULTS.sources.providers[id]
      if shipped and shipped.module == override.module then
        under.opts = vim.deepcopy(shipped.opts)
      else
        under.opts = nil
      end
    end
  end
end

---Rebuilds `options` from scratch and replaces it by identity: DEFAULTS, then
---a snippets preset, then every registration, with `configured` -- the user's
---own `setup()` table -- merged on top last, so it wins regardless of which
---of `setup()`, `add_source_provider()` or `add_filetype_source()` ran most recently.
local function resolve()
  local resolved = beneath(configured and configured.snippets and configured.snippets.preset)
  drop_repointed_opts(resolved.sources.providers)
  M.options = merge(resolved, configured or {})
end

---Validates, keeps the table, and re-resolves -- see `resolve()`.
---@param opts? zcmp.Config
function M.setup(opts)
  if opts ~= nil and type(opts) ~= 'table' then
    vim.notify(('zcmp.setup: expected a table, got %s'):format(type(opts)), vim.log.levels.WARN)
    opts = nil
  end
  local pruned = opts
  if opts then
    pruned = prune(opts, SHAPES, '', 'zcmp.setup')
    if pruned.sources and pruned.sources.providers then
      local layer = beneath(pruned.snippets and pruned.snippets.preset)
      for id, provider in pairs(pruned.sources.providers) do
        local under = layer.sources.providers[id]
        prune_shipped_opts(id, provider, 'zcmp.setup', provider.module or under and under.module)
      end
    end
    report_unknown_snippets_preset(pruned)
    if type(pruned.keymap) == 'table' then
      -- Lazy: keymap.lua requires this module at the top level.
      require('zcmp.keymap').check(pruned.keymap)
    end
  end
  -- A snapshot: a registration re-resolves from this table later, and the
  -- user editing theirs after setup() must change nothing.
  configured = pruned and vim.deepcopy(pruned)
  resolve()
end

---A key `SHAPES` cannot describe, because it describes values: the id a
---registration is filed under, which is the name a source list will look it up
---by. Nothing else can be filed under, so this is the one check that refuses.
---@param where string
---@param name string
---@param key any
---@return boolean
local function keyed(where, name, key)
  if type(key) == 'string' then
    return true
  end
  vim.notify(('%s: %s should be a string, got %s'):format(where, name, type(key)), vim.log.levels.WARN)
  return false
end

---Register a provider, whether or not setup() has run yet. Validated and
---copied on the same terms as one written into setup(): a registration is the
---same table by another door, and the plugin that made it goes on holding its
---own copy.
---@param id string
---@param provider zcmp.Provider
function M.add_source_provider(id, provider)
  if not keyed('zcmp.add_source_provider', 'id', id) then
    return
  end
  local pruned = prune({ [id] = provider }, { __any = PROVIDER_SHAPE }, 'sources.providers', 'zcmp.add_source_provider')
  if not pruned[id] then
    return
  end
  -- The registration's opts are shaped by the registration's module and
  -- nothing else: `apply_additions()` replaces the shipped provider wholesale,
  -- so one naming no module reaches none, and what an earlier setup() named
  -- for the id sits above -- `resolve()` files the registration underneath
  -- setup()'s table, and if setup() re-points the id `drop_repointed_opts()`
  -- drops these opts with it, unreported, since the module they were written
  -- for never sees them.
  prune_shipped_opts(id, pruned[id], 'zcmp.add_source_provider', pruned[id].module)
  additions.providers[id] = vim.deepcopy(pruned[id])
  resolve()
end

---Add providers to one filetype's list, whether or not setup() has run yet.
---@param filetype string
---@param ids string|string[]
function M.add_filetype_source(filetype, ids)
  ---@type string[]
  local adding = type(ids) == 'table' and ids or { ids }
  if not keyed('zcmp.add_filetype_source', 'filetype', filetype) then
    return
  end
  -- The third way to call this wrong, and the quietest: it would file an entry
  -- naming no sources, which resolves to exactly `sources.default` -- a call
  -- that did nothing, said nothing, and reads as the ids having been ignored.
  if next(adding) == nil then
    vim.notify(('zcmp.add_filetype_source: no provider ids for %q'):format(filetype), vim.log.levels.WARN)
    return
  end
  -- A string id no provider answers to is still added, as setup() would: that
  -- is `:ZCmp status`'s "no such provider", not a reason to drop the call. A
  -- non-string element is dropped, on the same terms prune() drops one from
  -- `sources.default` or a `per_filetype` list -- and if that empties the
  -- list, `pruned[filetype]` comes back nil and nothing is filed, the same as
  -- a table-shaped option that lost every entry.
  local pruned = prune({ [filetype] = adding }, { __any = { __list = 'string' } }, 'sources.per_filetype', 'zcmp.add_filetype_source')
  if not pruned[filetype] then
    return
  end
  add_ids(additions.per_filetype, filetype, pruned[filetype])
  resolve()
end

---Restore the defaults, registrations included. Used by tests.
function M.reset()
  additions = { providers = {}, per_filetype = {} }
  configured = nil
  resolve()
end

return M
