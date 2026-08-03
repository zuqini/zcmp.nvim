---Which buffers ZCmp drives, and every option it writes to get there.
---
---'complete' is derived from current state on each pass rather than appended
---to, because BufEnter and the LSP hooks reach this in either order and both
---have to end at the same value.

local api = vim.api
local config = require('zcmp.config')
local keymap = require('zcmp.keymap')
local sources = require('zcmp.sources')

local M = {}

---@type table<integer, { complete: string, autocomplete: boolean }>
local attached = {}

---@type table<string, any>?
local globals = nil

---@return string
function M.completeopt()
  local completion = config.options.completion
  local selection = completion.list.selection

  local opts = { 'menuone' }
  if config.options.fuzzy.enabled ~= false then
    opts[#opts + 1] = 'fuzzy'
  end
  if completion.documentation.auto_show ~= false then
    opts[#opts + 1] = 'popup'
  end
  -- 'noinsert' is the one flag 'autocomplete' ignores that is still
  -- load-bearing: vim.lsp.completion calls vim.fn.complete() itself and that
  -- path honours it. Without it the server's first item is inserted as you
  -- type, so `vim.` becomes `vim.F` and the next keystroke appends to it.
  if not selection.auto_insert then
    opts[#opts + 1] = 'noinsert'
  end
  -- 'autocomplete' forces 'noselect' on, and 'preselect' is what overrides it
  -- -- the only thing putting an item under the cursor for <cr>.
  if selection.preselect ~= false then
    opts[#opts + 1] = 'preselect'
  end
  return table.concat(opts, ',')
end

function M.apply_globals()
  globals = globals
    or {
      autocomplete = vim.go.autocomplete,
      autocompletedelay = vim.go.autocompletedelay,
      completeopt = vim.go.completeopt,
      shortmess = vim.go.shortmess,
    }

  -- Buffer-local opt-in, so a prompt or terminal buffer keeps core's own menu.
  vim.go.autocomplete = false
  -- Sources only run once the delay elapses, so this also bounds how often a
  -- directory is listed and a server asked. It suppresses nothing while typing
  -- faster than the value.
  vim.go.autocompletedelay = config.options.completion.trigger.delay_ms
  vim.go.completeopt = M.completeopt()
  -- Autotriggering everywhere would report 'match 1 of 9' on nearly every key.
  vim.opt.shortmess:append('c')
end

function M.restore_globals()
  if not globals then
    return
  end
  for name, value in pairs(globals) do
    vim.go[name] = value
  end
  globals = nil
end

---@param bufnr integer
local function wire(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not config.options.enabled(bufnr) then
    M.detach(bufnr)
    return
  end

  if not attached[bufnr] then
    attached[bufnr] = { complete = vim.bo[bufnr].complete, autocomplete = vim.bo[bufnr].autocomplete }
    keymap.apply(bufnr)
  end
  vim.bo[bufnr].autocomplete = config.options.completion.menu.auto_show ~= false
  vim.bo[bufnr].complete = sources.resolve(bufnr)
end

---The one place deciding which buffers this engine owns, reached from BufEnter
---and both LSP hooks. Scheduled because a scratch buffer is still buftype ''
---at BufEnter, and a detaching client is still attached while LspDetach runs.
---@param bufnr integer
function M.attach(bufnr)
  vim.schedule(function()
    wire(bufnr)
  end)
end

---Buffers opened before |zcmp.setup()| ran never see BufEnter.
function M.attach_all()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) then
      M.attach(bufnr)
    end
  end
end

---@param bufnr integer
function M.detach(bufnr)
  local saved = attached[bufnr]
  attached[bufnr] = nil
  keymap.remove(bufnr)
  if not saved or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].complete = saved.complete
  vim.bo[bufnr].autocomplete = saved.autocomplete
end

function M.detach_all()
  for bufnr in pairs(attached) do
    M.detach(bufnr)
  end
end

---@param bufnr integer
---@return boolean
function M.attached(bufnr)
  return attached[bufnr] ~= nil
end

return M
