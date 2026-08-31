---Which buffers ZCmp drives, and every option it writes to get there.
---
---'complete' is derived from current state on each pass rather than appended
---to, because BufEnter and the LSP hooks reach this in either order and both
---have to end at the same value.

local api = vim.api
local config = require('zcmp.config')
local keymap = require('zcmp.keymap')
local lsp = require('zcmp.lsp')
local sources = require('zcmp.sources')

local M = {}

---@type table<integer, { complete: string, autocomplete: boolean }>
local attached = {}

---Bumped by every wholesale detach, so that a wire() already sitting in the
---scheduler does not put back what |zcmp.disable()| has just taken.
local generation = 0

---@type table<string, any>?
local globals = nil

---@type table<string, boolean>?
local understood = nil

---'completeopt' raises E474 rather than ignoring a value it does not know, and
---`preselect` is newer than the 0.12.0 floor. Asked once, by trying each.
---`menuone` is the base every probe is written against, so it is never a
---question.
---@param flag string
---@return boolean
local function known(flag)
  if not understood then
    understood = {}
    local saved = vim.go.completeopt
    for _, name in ipairs({ 'fuzzy', 'popup', 'noinsert', 'noselect', 'preselect' }) do
      understood[name] = pcall(function()
        vim.go.completeopt = 'menuone,' .. name
      end)
    end
    vim.go.completeopt = saved
  end
  return understood[flag] == true
end

---Whether this Neovim can put an item under the cursor while 'autocomplete' is
---on. `:checkhealth zcmp` says so when it cannot.
---@return boolean
function M.can_preselect()
  return known('preselect')
end

---@return string
function M.completeopt()
  local completion = config.options.completion
  local selection = completion.list.selection

  local opts = { 'menuone' }
  if config.options.fuzzy.enabled ~= false and known('fuzzy') then
    opts[#opts + 1] = 'fuzzy'
  end
  if completion.documentation.auto_show ~= false and known('popup') then
    opts[#opts + 1] = 'popup'
  end
  -- 'noinsert' is the one flag 'autocomplete' ignores that is still
  -- load-bearing: vim.lsp.completion calls vim.fn.complete() itself and that
  -- path honours it. Without it the server's first item is inserted as you
  -- type, so `vim.` becomes `vim.F` and the next keystroke appends to it.
  if not selection.auto_insert and known('noinsert') then
    opts[#opts + 1] = 'noinsert'
  end
  -- 'autocomplete' forces 'noselect' on for the menus it opens, but
  -- vim.lsp.completion's restart -- the menu vim.fn.complete() rebuilds once
  -- a server answers -- does not, and selects its first item unless the flag
  -- is written. Written here so both obey the same rule: 'preselect' is what
  -- overrides it, for an item a source marked -- the only thing putting an
  -- item under the cursor for <cr>.
  if known('noselect') then
    opts[#opts + 1] = 'noselect'
  end
  if selection.preselect ~= false and known('preselect') then
    opts[#opts + 1] = 'preselect'
  end
  return table.concat(opts, ',')
end

---'autocompletedelay' takes a non-negative whole number and raises on a float,
---which would abandon apply_globals() with 'autocomplete' already off: core's
---own completion switched off and ZCmp not yet attached to anything. The
---type is config's to check; what is left here is the range, which no shape
---can say.
---@return integer? ms nil when the value is no kind of number to round
local function delay()
  local ms = config.options.completion.menu.auto_show_delay_ms
  -- Clamped at what the option takes: above 2^31 it raises the same E474 a
  -- float does, and math.floor of a large float is still a float. ms == ms
  -- excludes NaN, the one value with nothing to round.
  local wanted = ms == ms and math.min(math.max(0, math.floor(ms)), 2147483647) or nil
  if wanted ~= ms then
    vim.notify_once(
      ('zcmp: completion.menu.auto_show_delay_ms is milliseconds as a whole number, not %s'):format(vim.inspect(ms)),
      vim.log.levels.WARN
    )
  end
  return wanted
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
  -- The 'complete' sources only run once the delay elapses, so this also
  -- bounds how often a directory is listed. It does not reach
  -- vim.lsp.completion's autotrigger, which is not a 'complete' source: that
  -- asks the server on every trigger character, undelayed, and is switched
  -- off with `auto_show` (see lsp.attach). It suppresses nothing while typing
  -- faster than the value.
  vim.go.autocompletedelay = delay() or globals.autocompletedelay
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

---'complete' raises rather than ignoring a flag it does not understand, and
---every part of the value can come from somewhere else: a provider's flags,
---the cap it asks for, a third party's `source()`. A buffer left half-wired --
---mapped and autocompleting, with the option unwritten -- is worse than one
---ZCmp never took, and `attached` is set by the time the write runs.
---@param bufnr integer
---@return boolean
local function set_complete(bufnr)
  local ok, resolved = pcall(sources.resolve, bufnr)
  if not ok then
    vim.notify_once(('zcmp: a source failed to resolve: %s'):format(resolved), vim.log.levels.ERROR)
    return false
  end

  local written, err = pcall(function()
    vim.bo[bufnr].complete = resolved
  end)
  if not written then
    vim.notify_once(("zcmp: 'complete' would not take %q: %s"):format(resolved, err), vim.log.levels.ERROR)
  end
  return written
end

---@param bufnr integer
local function wire(bufnr)
  -- Unloaded counts as gone, the rule attach_all() already applies: :bdelete
  -- fires LspDetach before BufDelete, so the pass it scheduled lands after
  -- the detach, on a buffer that is valid, unlisted, and not coming back.
  if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
    M.detach(bufnr)
    return
  end
  -- The same nvim_buf_call wrap as sources' in_buffer, for the same reason:
  -- a no-argument predicate reading vim.bo/vim.b must see bufnr as current.
  local ok, enabled = pcall(vim.api.nvim_buf_call, bufnr, function()
    return config.options.enabled(bufnr)
  end)
  if not ok then
    vim.notify_once(('zcmp: the `enabled` option raised: %s'):format(enabled), vim.log.levels.ERROR)
  end
  if not ok or not enabled then
    M.detach(bufnr)
    return
  end

  if not attached[bufnr] then
    attached[bufnr] = { complete = vim.bo[bufnr].complete, autocomplete = vim.bo[bufnr].autocomplete }
    local applied, err = pcall(keymap.apply, bufnr)
    if not applied then
      vim.notify_once(('zcmp: keymap.apply raised: %s'):format(err), vim.log.levels.ERROR)
      M.detach(bufnr)
      return
    end
  end
  vim.bo[bufnr].autocomplete = config.options.completion.menu.auto_show ~= false
  if not set_complete(bufnr) then
    M.detach(bufnr)
    return
  end
  -- Same pass, same predicate: |vim.lsp.completion| is one more thing ZCmp
  -- switches on, so a buffer it does not drive must not get it either.
  lsp.sync(bufnr, sources.provider(bufnr, 'lsp'))
end

---The one place deciding which buffers this engine owns, reached from BufEnter,
---FileType and both LSP hooks. Scheduled because a scratch buffer is still
---buftype '' at BufEnter, and a detaching client is still attached while
---LspDetach runs.
---@param bufnr integer
function M.attach(bufnr)
  local scheduled = generation
  vim.schedule(function()
    if scheduled == generation then
      wire(bufnr)
    end
  end)
end

---Forgets an LSP client synchronously, then ends in |M.attach()| -- the
---reason this cannot simply be M.attach(): forgetting has to happen now, not
---on the scheduled pass M.attach() runs. A buffer re-read (`:e`, `:e!`) fires
---`on_detach` and reattaches the same client id synchronously, before that
---pass lands, so `lsp.sync()` would otherwise still find the client marked
---wired and do nothing. `client_id` is nil for an LspDetach with no `data` --
---`:doautocmd LspDetach` or `nvim_exec_autocmds('LspDetach', ...)` fire it
---that way -- in which case there is nothing to forget and this is exactly
---|M.attach()|.
---@param bufnr integer
---@param client_id? integer
function M.forget_client(bufnr, client_id)
  if client_id then
    lsp.forget(bufnr, client_id)
  end
  M.attach(bufnr)
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
  lsp.detach(bufnr)
  if not saved or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].complete = saved.complete
  vim.bo[bufnr].autocomplete = saved.autocomplete
end

function M.detach_all()
  generation = generation + 1
  for _, bufnr in ipairs(vim.tbl_keys(attached)) do
    M.detach(bufnr)
  end
  lsp.detach_all()
end

---@param bufnr integer
---@return boolean
function M.attached(bufnr)
  return attached[bufnr] ~= nil
end

return M
