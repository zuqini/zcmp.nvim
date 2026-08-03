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
---in Select mode as well as Insert.
local SNIPPET_COMMANDS = {
  snippet_forward = true,
  snippet_backward = true,
  snippet_delete = true,
}

local SHARED = {
  ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
  ['<Up>'] = { 'select_prev', 'fallback' },
  ['<Down>'] = { 'select_next', 'fallback' },
  ['<C-p>'] = { 'select_prev', 'fallback' },
  ['<C-n>'] = { 'select_next', 'fallback' },
  ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
  ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
  ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
  ['<C-y>'] = { 'select_and_accept' },
  ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
}

---@param keymap table<string, zcmp.Command[]>
---@return table<string, zcmp.Command[]>
local function preset(keymap)
  return vim.tbl_extend('force', SHARED, keymap)
end

---@type table<zcmp.KeymapPreset, table<string, zcmp.Command[]>>
M.presets = {
  none = {},
  default = preset({
    ['<C-e>'] = { 'hide' },
    ['<Tab>'] = { 'snippet_forward', 'fallback' },
  }),
  ['super-tab'] = preset({
    ['<C-e>'] = { 'hide', 'fallback' },
    ['<Tab>'] = { 'select_and_accept', 'snippet_forward', 'fallback' },
  }),
  enter = preset({
    ['<C-e>'] = { 'hide', 'fallback' },
    ['<CR>'] = { 'accept', 'fallback' },
    ['<Tab>'] = { 'snippet_forward', 'fallback' },
  }),
}

---@type table<integer, { keys: { mode: string, lhs: string }[], captured: table<string, table> }>
local installed = {}

---The preset with the user's own entries over it. An entry of `{}` is how a
---key is left alone.
---@return table<string, zcmp.Command[]>
function M.resolve()
  local keymap = config.options.keymap
  local name = keymap.preset or 'default'
  if not M.presets[name] then
    vim.notify_once(('zcmp: %q is not a keymap preset'):format(name), vim.log.levels.WARN)
    name = 'default'
  end

  local resolved = vim.deepcopy(M.presets[name])
  for lhs, entry in pairs(keymap) do
    if lhs ~= 'preset' then
      resolved[lhs] = entry
    end
  end
  return resolved
end

---@param entry zcmp.Command[]
---@return string[]
local function modes(entry)
  for _, command in ipairs(entry) do
    if SNIPPET_COMMANDS[command] then
      return { 'i', 's' }
    end
  end
  return { 'i' }
end

---A name resolves against |zcmp-commands| only. The predicates live in the
---same module and answer a question rather than doing anything, so binding one
---would swallow the key; naming one is the same mistake as a typo.
---@param command zcmp.Command
---@return function?
local function resolve_command(command)
  if type(command) == 'function' then
    return command
  end
  if commands.predicates[command] then
    return nil
  end
  return commands[command]
end

---@param mode string
---@param lhs string
---@param entry zcmp.Command[]
---@param captured table<string, table>
local function run(mode, lhs, entry, captured)
  for _, command in ipairs(entry) do
    if command == 'fallback' or command == 'fallback_to_mappings' then
      return fallback.run(mode, lhs, captured[mode .. lhs])
    end

    local fn = resolve_command(command)
    if type(fn) ~= 'function' then
      vim.notify_once(('zcmp: %q is not a keymap command'):format(tostring(command)), vim.log.levels.WARN)
    else
      local ok, handled = pcall(fn, type(command) == 'function' and commands or nil)
      if not ok then
        vim.notify(('zcmp: %s'):format(handled), vim.log.levels.ERROR)
      elseif handled then
        return
      end
    end
  end
end

---@param map table
---@param mode string
---@param bufnr integer
local function restore(map, mode, bufnr)
  local opts = {
    buffer = bufnr,
    expr = map.expr == 1,
    noremap = map.noremap == 1,
    nowait = map.nowait == 1,
    silent = map.silent == 1,
    desc = map.desc,
  }
  if opts.expr then
    opts.replace_keycodes = map.replace_keycodes == 1
  end
  pcall(vim.keymap.set, mode, map.lhs, map.callback or map.rhs or '', opts)
end

---@param bufnr integer
function M.apply(bufnr)
  M.remove(bufnr)

  local captured, keys = {}, {}
  for lhs, entry in pairs(M.resolve()) do
    if type(entry) == 'table' and #entry > 0 then
      for _, mode in ipairs(modes(entry)) do
        captured[mode .. lhs] = fallback.capture(bufnr, mode, lhs)
        vim.keymap.set(mode, lhs, function()
          run(mode, lhs, entry, captured)
        end, { buffer = bufnr, desc = 'zcmp' })
        keys[#keys + 1] = { mode = mode, lhs = lhs }
      end
    end
  end

  installed[bufnr] = { keys = keys, captured = captured }
end

---Take ZCmp's mappings back out, putting back whatever they displaced.
---@param bufnr integer
function M.remove(bufnr)
  local state = installed[bufnr]
  installed[bufnr] = nil
  if not state or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  for _, key in ipairs(state.keys) do
    pcall(vim.keymap.del, key.mode, key.lhs, { buffer = bufnr })
    local previous = state.captured[key.mode .. key.lhs]
    if previous then
      restore(previous, key.mode, bufnr)
    end
  end
end

---@param bufnr integer
---@return { mode: string, lhs: string }[]
function M.installed(bufnr)
  return installed[bufnr] and installed[bufnr].keys or {}
end

return M
