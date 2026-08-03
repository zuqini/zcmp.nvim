---What `'fallback'` in a keymap entry means: the key goes to whoever had it
---before ZCmp did.
---
---That is the whole of ZCmp's relationship with other plugins that map insert
---mode. A `<CR>` belonging to an autopair plugin keeps working because this
---finds it and runs it, not because ZCmp knows the plugin exists.

local api = vim.api

local M = {}

---The 'i' flag for the same reason `zcmp.api` feeds with it: these keys stand
---in for the one that was pressed, so they belong in front of the queue.
---@param keys string
---@param remap boolean
local function feed(keys, remap)
  api.nvim_feedkeys(keys, remap and 'im' or 'in', false)
end

---@param map table A |maparg()|-shaped dict
---@param lhs string
local function execute(map, lhs)
  local keys, remap
  if map.callback then
    if map.expr ~= 1 then
      map.callback()
      return
    end
    local result = map.callback()
    if type(result) ~= 'string' then
      return
    end
    keys = map.replace_keycodes == 1 and vim.keycode(result) or result
  else
    keys = map.rhs or ''
    if map.expr == 1 then
      local ok, evaluated = pcall(api.nvim_eval, keys)
      keys = ok and type(evaluated) == 'string' and evaluated or ''
    end
    keys = vim.keycode(keys)
  end

  remap = map.noremap ~= 1
  -- A mapping whose right-hand side starts with its own key would otherwise
  -- come straight back here.
  if remap and vim.startswith(keys, vim.keycode(lhs)) then
    remap = false
  end
  feed(keys, remap)
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

---@param mode string
---@param lhs string
---@param captured? table The dict |zcmp.fallback.capture()| returned
function M.run(mode, lhs, captured)
  local map = captured or find(api.nvim_get_keymap(mode), lhs)
  if not map then
    feed(vim.keycode(lhs), false)
    return
  end
  execute(map, lhs)
end

return M
