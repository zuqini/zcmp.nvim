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
        opts = { max_items = 250 },
      },
      snippets = {
        name = 'Snippets',
        module = 'zsnip.complete',
        -- zcmp owns 'complete'; zsnip caps and documents for itself.
        opts = { complete = false, documentation = false, limit = 30 },
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
local function validate(opts, shapes, path)
  for key, value in pairs(opts) do
    local name = path == '' and tostring(key) or path .. '.' .. tostring(key)
    local shape = shapes[key] or shapes.__any
    if not shape then
      vim.notify(('zcmp.setup: unknown option %q'):format(name), vim.log.levels.WARN)
    elseif type(shape) == 'table' and shape[1] == nil then
      if type(value) ~= 'table' then
        vim.notify(('zcmp.setup: %s should be a table, got %s'):format(name, type(value)), vim.log.levels.WARN)
      else
        validate(value, shape, name)
      end
    elseif not vim.tbl_contains(types(shape), type(value)) then
      vim.notify(
        ('zcmp.setup: %s should be %s, got %s'):format(name, table.concat(types(shape), ' or '), type(value)),
        vim.log.levels.WARN
      )
    end
  end
end

---Deep merge, except that a non-empty list replaces rather than extends: a
---`sources.default` of two entries means those two, not those two plus the
---four that were there.
---@param base any
---@param override any
---@return any
local function merge(base, override)
  if type(base) ~= 'table' then
    return override
  end
  -- A table-shaped option handed a scalar is a config error, already reported.
  -- Keeping the default is what lets the rest of the config still apply.
  if type(override) ~= 'table' then
    return base
  end
  if #override > 0 and vim.islist(override) then
    return vim.deepcopy(override)
  end
  local merged = vim.deepcopy(base)
  for key, value in pairs(override) do
    merged[key] = merge(merged[key], value)
  end
  return merged
end

---Replaces `options` rather than editing it in place, so a reader can tell a
---late setup() by identity alone.
---@param opts? zcmp.Config
function M.setup(opts)
  if opts then
    validate(opts, SHAPES, '')
  end
  M.options = merge(DEFAULTS, opts or {})
end

---Restore the defaults. Used by tests.
function M.reset()
  M.options = vim.deepcopy(DEFAULTS)
end

return M
