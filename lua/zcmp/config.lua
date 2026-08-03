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
        -- 'o' is the LSP omnifunc, only worth listing once a server can answer.
        flags = { 'o' },
        available = function(bufnr)
          return require('zcmp.lsp').available(bufnr)
        end,
        opts = { autotrigger = true, extend_trigger_characters = true },
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
    trigger = { delay_ms = 200 },
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
---its preset the same way it beats any other default.
---
---vim.lsp.completion expands a server's snippet items through vim.snippet
---regardless (see lsp.lua), so under 'luasnip' both engines can hold a live
---session: every answer asks LuaSnip first and falls through.
---@type table<string, fun(base: zcmp.ResolvedConfig)>
local PRESETS = {
  default = function() end,
  luasnip = function(base)
    base.snippets.expand = function(body)
      require('luasnip').lsp_expand(body)
    end
    base.snippets.active = function(filter)
      local luasnip = require('luasnip')
      if filter and filter.direction then
        return luasnip.jumpable(filter.direction) or vim.snippet.active(filter)
      end
      return luasnip.locally_jumpable(1) or vim.snippet.active(filter)
    end
    base.snippets.jump = function(direction)
      local luasnip = require('luasnip')
      if luasnip.jumpable(direction) then
        luasnip.jump(direction)
      else
        vim.snippet.jump(direction)
      end
    end
    base.sources.providers.snippets = {
      name = 'Snippets',
      module = 'zcmp.sources.snippets.luasnip',
    }
  end,
}

local PROVIDER_SHAPE = {
  name = 'string',
  flags = 'table',
  module = 'string',
  opts = 'table',
  max_items = 'number',
  enabled = { 'boolean', 'function' },
  available = 'function',
}

---Mirrors DEFAULTS. A leaf is the accepted `type()`s; `__any` describes the
---value under keys the user names (a lhs, a filetype, a provider id).
local SHAPES = {
  enabled = 'function',
  keymap = { preset = 'string', __any = 'table' },
  sources = {
    default = 'table',
    per_filetype = { __any = 'table' },
    providers = { __any = PROVIDER_SHAPE },
  },
  completion = {
    menu = { auto_show = 'boolean' },
    documentation = { auto_show = 'boolean' },
    list = {
      max_items = 'number',
      selection = { preselect = 'boolean', auto_insert = 'boolean' },
    },
    trigger = { delay_ms = 'number' },
  },
  fuzzy = { enabled = 'boolean' },
  snippets = { preset = 'string', expand = 'function', active = 'function', jump = 'function' },
  signature = { enabled = 'boolean' },
  appearance = { kind_hl = { 'string', 'boolean' } },
}

---@type zcmp.ResolvedConfig
M.options = vim.deepcopy(DEFAULTS)

---@param shape string|string[]
---@return string[]
local function types(shape)
  return type(shape) == 'table' and shape or { shape }
end

---An unknown key is almost always a typo for a known one, and a merged-in
---`max_item` or `documention` is a silent no-op that reads exactly like the
---option not working. Reported rather than raised: a config that is wrong in
---one place should still get the rest.
---@param opts table
---@param shapes table
---@param path string
---@param where string The call being validated, for the message
local function validate(opts, shapes, path, where)
  for key, value in pairs(opts) do
    local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
    local shape = shapes[key] or shapes.__any
    if not shape then
      vim.notify(('%s: unknown option %q'):format(where, name), vim.log.levels.WARN)
    elseif type(shape) == 'table' and shape[1] == nil then
      if type(value) ~= 'table' then
        vim.notify(('%s: %s should be a table, got %s'):format(where, name, type(value)), vim.log.levels.WARN)
      else
        validate(value, shape, name, where)
      end
    elseif not vim.tbl_contains(types(shape), type(value)) then
      vim.notify(
        ('%s: %s should be %s, got %s'):format(where, name, table.concat(types(shape), ' or '), type(value)),
        vim.log.levels.WARN
      )
    end
  end
end

---A preset ZCmp does not know is not silently the default one -- that reads
---exactly like the preset being broken. Said out loud instead, with the way
---any engine plugs in without one.
---@param opts table
local function report_unknown_preset(opts)
  local snippets = opts.snippets
  if type(snippets) ~= 'table' then
    return
  end
  if snippets.preset and not PRESETS[snippets.preset] then
    vim.notify(
      ('zcmp.setup: %q is not a snippets preset; ZCmp has \'default\' and \'luasnip\'. '):format(
        tostring(snippets.preset)
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
---`opts`: free-form third-party data, a map, and merged as one. A list with a
---hole in it is no list either, for the same reason it is not one to `ipairs`.
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
  -- A table-shaped option handed a scalar is a config error, already reported.
  -- Keeping the default is what lets the rest of the config still apply.
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
    sources.providers[id] = provider
  end
  for filetype, ids in pairs(additions.per_filetype) do
    add_ids(sources.per_filetype, filetype, ids)
  end
end

---Replaces `options` rather than editing it in place, so a reader can tell a
---late setup() by identity alone. Registrations made before it ran go
---underneath, so that an explicit `opts` still wins.
---@param opts? zcmp.Config
function M.setup(opts)
  if opts then
    validate(opts, SHAPES, '', 'zcmp.setup')
    report_unknown_preset(opts)
  end
  local base = vim.deepcopy(DEFAULTS)
  local preset = type(opts) == 'table' and type(opts.snippets) == 'table' and opts.snippets.preset
  if type(preset) == 'string' and PRESETS[preset] then
    PRESETS[preset](base)
  end
  apply_additions(base.sources)
  M.options = merge(base, opts or {})
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
function M.add_provider(id, provider)
  if not keyed('zcmp.add_source_provider', 'id', id) then
    return
  end
  validate({ [id] = provider }, { __any = PROVIDER_SHAPE }, 'sources.providers', 'zcmp.add_source_provider')
  -- Two copies rather than one shared between them: `additions` outlives every
  -- `options` setup() replaces, and must not come to alias the live one.
  additions.providers[id] = vim.deepcopy(provider)
  M.options.sources.providers[id] = vim.deepcopy(provider)
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
  if #adding == 0 then
    vim.notify(('zcmp.add_filetype_source: no provider ids for %q'):format(filetype), vim.log.levels.WARN)
    return
  end
  -- Reported and then added anyway, as setup() would: an id no provider answers
  -- to is `:ZCmp status`'s "no such provider", not a reason to drop the call.
  validate(adding, { __any = 'string' }, 'sources.per_filetype.' .. filetype, 'zcmp.add_filetype_source')
  add_ids(additions.per_filetype, filetype, adding)
  add_ids(M.options.sources.per_filetype, filetype, adding)
end

---Restore the defaults, registrations included. Used by tests.
function M.reset()
  additions = { providers = {}, per_filetype = {} }
  M.options = vim.deepcopy(DEFAULTS)
end

return M
