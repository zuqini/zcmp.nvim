---Shared test scaffolding: throwaway buffers and directories, stubs for the
---things a headless runner has no real version of (a popup menu, a keystroke),
---and the `assert.contains` assertion.

local luassert = require('luassert')
local say = require('say')

local M = {}

-- `assert.contains(tbl, value)` — a list-membership assertion luassert has no
-- built-in for. Registered as a real luassert assertion (rather than a bare
-- helper that raises via error()) so a failed containment check is classified
-- by busted as a 'failure', not an 'error', like every other assertion.
local function table_contains(_, arguments)
  local tbl = arguments[1]
  if type(tbl) ~= 'table' then
    return false
  end
  for _, value in ipairs(tbl) do
    if value == arguments[2] then
      return true
    end
  end
  return false
end

say:set('assertion.contains.positive', 'Expected table to contain value.\nTable:\n%s\nValue:\n%s')
say:set('assertion.contains.negative', 'Expected table to not contain value.\nTable:\n%s\nValue:\n%s')
luassert:register(
  'assertion',
  'contains',
  table_contains,
  'assertion.contains.positive',
  'assertion.contains.negative'
)

---@type string[]
local tempdirs = {}
---@type integer[]
local buffers = {}
---@type fun()[]
local undo = {}

---@return string
function M.tempdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  tempdirs[#tempdirs + 1] = dir
  return dir
end

---@param path string
---@param contents? string
function M.write(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(vim.split(contents or '', '\n'), path)
end

---A normal, listed buffer — what the default `enabled` accepts.
---@param lines? string[]
---@param name? string
---@return integer
function M.buffer(lines, name)
  local bufnr = vim.api.nvim_create_buf(true, false)
  buffers[#buffers + 1] = bufnr
  if name then
    vim.api.nvim_buf_set_name(bufnr, name)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { '' })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, #(lines and lines[1] or '') })
  return bufnr
end

---Replace `tbl[key]` until |helpers.cleanup()|.
---@param tbl table
---@param key string
---@param value any
function M.stub(tbl, key, value)
  local original = rawget(tbl, key)
  tbl[key] = value
  undo[#undo + 1] = function()
    tbl[key] = original
  end
end

---Pretend a completion menu is up. `state` is what |complete_info()| answers;
---`false` is no menu at all.
---@param state false|table
function M.pum(state)
  M.stub(vim.fn, 'pumvisible', function()
    return state and 1 or 0
  end)
  M.stub(vim.fn, 'complete_info', function()
    return state or { selected = -1 }
  end)
end

---Pretend the editor is in `mode`; several commands decline to act outside
---Insert mode, and a test runner is in Normal.
---@param mode string
function M.mode(mode)
  M.stub(vim.fn, 'mode', function()
    return mode
  end)
end

---The keys zcmp fed while `fn` ran, as termcodes.
---@param fn fun()
---@return string[]
function M.keys(fn)
  local feedkeys = vim.api.nvim_feedkeys
  local fed = {}
  vim.api.nvim_feedkeys = function(keys)
    fed[#fed + 1] = keys
  end
  local ok, err = pcall(fn)
  vim.api.nvim_feedkeys = feedkeys
  if not ok then
    error(err)
  end
  return fed
end

---Everything vim.notify() and vim.notify_once() were told while `fn` ran.
---@param fn fun()
---@return { message: string, level: integer? }[]
function M.notifications(fn)
  local notify, notify_once = vim.notify, vim.notify_once
  local captured = {}
  vim.notify = function(message, level)
    captured[#captured + 1] = { message = message, level = level }
  end
  vim.notify_once = vim.notify
  local ok, err = pcall(fn)
  vim.notify, vim.notify_once = notify, notify_once
  if not ok then
    error(err)
  end
  return captured
end

---@param captured { message: string }[]
---@param pattern string
---@return boolean
function M.notified(captured, pattern)
  for _, notification in ipairs(captured) do
    if tostring(notification.message):find(pattern, 1, true) then
      return true
    end
  end
  return false
end

---`zcmp.buffer.attach()` schedules, because the state it reads is not final
---until the autocmd that triggered it has returned.
---@param bufnr integer
function M.settle(bufnr)
  local buffer = require('zcmp.buffer')
  vim.wait(200, function()
    return buffer.attached(bufnr)
  end)
end

---A fresh config, no buffer attached, no provider module started.
function M.reset()
  require('zcmp').disable()
  require('zcmp.config').reset()
  require('zcmp.sources').reset()
end

function M.cleanup()
  for i = #undo, 1, -1 do
    undo[i]()
  end
  undo = {}

  require('zcmp').disable()
  require('zcmp.commands').remove()
  require('zcmp.config').reset()
  require('zcmp.sources').reset()

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  buffers = {}

  for _, dir in ipairs(tempdirs) do
    vim.fn.delete(dir, 'rf')
  end
  tempdirs = {}
end

return M
