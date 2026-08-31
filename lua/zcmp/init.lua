---ZCmp.nvim -- a completion engine's configuration, over Neovim's own
---completion.
---
---Since 0.12 Neovim opens the menu as you type ('autocomplete'), takes a
---function as a source ('complete'), fuzzy-matches, ranks and time-slices what
---the sources answer, and draws the documentation popup. What it does not ship
---is a configuration for any of that. ZCmp is that layer: sources, keymaps and
---options in one blink.cmp-shaped table, and nothing of its own between your
---keystroke and the menu.
---
---```lua
---require('zcmp').setup({
---  keymap = { preset = 'enter' },
---  sources = { default = { 'lsp', 'path', 'snippets', 'buffer' } },
---})
---```

local api = require('zcmp.api')
local appearance = require('zcmp.appearance')
local buffer = require('zcmp.buffer')
local config = require('zcmp.config')
-- init's one direct edge into lsp.lua: everything else per-buffer goes
-- through buffer.lua, the lifecycle façade. `buffer.lua` already requires
-- this at its own top, so nothing is deferred by requiring it lazily here.
local lsp = require('zcmp.lsp')
local sources = require('zcmp.sources')

local M = {}

---The plugin's own version. Kept in step with the tag by release-please --
---see `release-please-config.json` -- so that a bug report can say which zcmp
---it is about, which `:checkhealth zcmp` asks for.
M.version = '0.1.0' -- x-release-please-version

local GROUP = 'zcmp'

local enabled = false

local function autocmds()
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })

  -- FileType because `sources.per_filetype` is keyed off it and `:setfiletype`
  -- can follow the buffer being entered; the LSP hooks because a client
  -- arriving or leaving changes both what 'complete' should say and whether
  -- |vim.lsp.completion| belongs on the buffer.
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType', 'LspAttach', 'LspDetach' }, {
    group = group,
    callback = function(args)
      if args.event == 'LspDetach' then
        buffer.forget_client(args.buf, args.data and args.data.client_id)
      else
        buffer.attach(args.buf)
      end
    end,
  })

  -- Nothing else drops a buffer's entry, and a long session opens a great many.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      buffer.detach(args.buf)
    end,
  })

  -- Here rather than in the sources that need it: the relocation being undone
  -- is |vim.lsp.completion|'s restart, which ZCmp switches on, so putting the
  -- run back is ZCmp's to do -- for every reason the menu closed, since a
  -- selected item's word is in the buffer whether it was accepted or discarded
  -- by typing on, and a relocated one is wrong either way.
  vim.api.nvim_create_autocmd('CompleteDone', {
    group = group,
    callback = function()
      sources.trim_head()
    end,
  })

  -- Restored before the scheme runs and applied after: a scheme that leaves
  -- these two groups alone would otherwise have ZCmp's own colours captured
  -- as the ones to give back.
  vim.api.nvim_create_autocmd('ColorSchemePre', {
    group = group,
    callback = function()
      appearance.restore()
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      appearance.apply()
    end,
  })
end

---Optional in the sense that every default works -- but nothing is wired up
---until it runs, which is the one call a config needs.
---@param opts? zcmp.Config
function M.setup(opts)
  config.setup(opts)
  -- Lazy on purpose: commands.lua requires 'zcmp' at its own top level, so
  -- this must stay inside setup() rather than move to init.lua's own top.
  require('zcmp.commands').create()
  M.enable()
end

---Take over completion: options, autocmds, and every buffer already open.
---
---Detaches first, so that a second |zcmp.setup()| re-derives the mappings as
---well as the options -- a buffer already attached is one `wire()` leaves the
---keymaps of alone.
---
---Forgets which provider modules have started, so that one `disable()` left
---missing -- not on the runtimepath, or otherwise unable to start -- gets a
---fresh attempt rather than the memo from its previous life. Every other
---piece of state `disable()` gives back is likewise rebuilt from scratch here;
---this is the one `disable()` itself cannot touch, since forgetting it while
---disabled would leave nothing to act on the memory.
---
---Does nothing at all below the 0.12.0 floor: the first thing it reads is an
---option that Neovim does not have, and an unknown-option traceback out of a
---buffer module names nothing a user can act on. Said here rather than in
---setup(), because this is the door every other way in goes through.
function M.enable()
  if vim.fn.has('nvim-0.12') == 0 then
    vim.notify('zcmp: Neovim 0.12.0+ is required', vim.log.levels.ERROR)
    return
  end
  sources.reset()
  buffer.detach_all()
  -- Restored before it is re-applied, so a second setup() that turns the
  -- highlight off leaves the group as apply() found it rather than as the
  -- first setup() left it.
  appearance.restore()
  appearance.apply()
  buffer.apply_globals()
  autocmds()
  buffer.attach_all()
  enabled = true
end

---Hand completion back: mappings are removed, the options ZCmp set are
---restored, buffers keep whatever 'complete' they had before, and
---|vim.lsp.completion| is switched off for every client of a buffer ZCmp
---drove -- including one a user's own `LspAttach` handler had already
---switched it on for.
function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, GROUP)
  buffer.detach_all()
  buffer.restore_globals()
  appearance.restore()
  enabled = false
end

---Whether |zcmp.enable()| has run and |zcmp.disable()| has not -- the engine
---switch, for every buffer alike. Not blink.cmp's `is_enabled()`, which
---evaluates the `enabled` predicate for the current buffer; `:ZCmp status`
---reports that (as "attached"/"not attached") for the current one.
---@return boolean
function M.is_enabled()
  return enabled
end

---Re-read the source list in every buffer ZCmp drives, and start any provider
---module that has arrived since. What `:ZCmp reload` runs. Does nothing while
---disabled: |zcmp.enable()| forgets which modules have started on its own, so
---there is no state left here to reload into.
function M.reload()
  if not enabled then
    return
  end
  sources.reset()
  buffer.detach_all()
  buffer.attach_all()
end

---Re-derive 'complete' where the source list has just changed underneath it.
local function refresh()
  if enabled then
    buffer.attach_all()
  end
end

---Register a provider. It serves nothing until a `sources.default` or
---`sources.per_filetype` list names it; see |zcmp-providers|. Order-free: a
---call before |zcmp.setup()| survives it.
---@param id string
---@param provider zcmp.Provider
function M.add_source_provider(id, provider)
  config.add_source_provider(id, provider)
  refresh()
end

---Add providers to one filetype's list, on top of `sources.default`.
---Order-free: a call before |zcmp.setup()| survives it.
---@param filetype string
---@param ids string|string[]
function M.add_filetype_source(filetype, ids)
  config.add_filetype_source(filetype, ids)
  refresh()
end

---Capabilities to hand a language server.
---@param override? lsp.ClientCapabilities
---@param include_nvim_defaults? boolean Default true
---@return lsp.ClientCapabilities
function M.get_lsp_capabilities(override, include_nvim_defaults)
  return lsp.capabilities(override, include_nvim_defaults)
end

-- The keymap commands, as a public API: what a `keymap` entry names by string,
-- callable by hand. See |zcmp-commands|.
M.show = api.show
M.show_on_keyword = api.show_on_keyword
M.hide = api.hide
M.cancel = api.cancel
M.is_visible = api.is_visible
M.is_menu_visible = api.is_menu_visible
M.select_next = api.select_next
M.select_prev = api.select_prev
M.accept = api.accept
M.select_and_accept = api.select_and_accept
M.snippet_forward = api.snippet_forward
M.snippet_backward = api.snippet_backward
M.snippet_delete = api.snippet_delete
M.is_snippet_active = api.is_snippet_active
M.snippet_active = api.snippet_active
M.show_documentation = api.show_documentation
M.hide_documentation = api.hide_documentation
M.is_documentation_visible = api.is_documentation_visible
M.scroll_documentation_up = api.scroll_documentation_up
M.scroll_documentation_down = api.scroll_documentation_down
M.show_signature = api.show_signature
M.hide_signature = api.hide_signature
M.is_signature_visible = api.is_signature_visible

return M
