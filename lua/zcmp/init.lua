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
      buffer.attach(args.buf)
    end,
  })

  -- Nothing else drops a buffer's entry, and a long session opens a great many.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function(args)
      buffer.detach(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      appearance.forget()
      appearance.apply()
    end,
  })
end

---Optional in the sense that every default works -- but nothing is wired up
---until it runs, which is the one call a config needs.
---@param opts? zcmp.Config
function M.setup(opts)
  config.setup(opts)
  require('zcmp.commands').create()
  M.enable()
end

---Take over completion: options, autocmds, and every buffer already open.
---
---Detaches first, so that a second |zcmp.setup()| re-derives the mappings as
---well as the options -- a buffer already attached is one `wire()` leaves the
---keymaps of alone.
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
  buffer.detach_all()
  appearance.apply()
  buffer.apply_globals()
  autocmds()
  buffer.attach_all()
  enabled = true
end

---Hand completion back: mappings are removed, the options ZCmp set are
---restored, buffers keep whatever 'complete' they had before, and every
---client ZCmp switched |vim.lsp.completion| on for is switched back.
function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, GROUP)
  buffer.detach_all()
  buffer.restore_globals()
  appearance.restore()
  enabled = false
end

---@return boolean
function M.is_enabled()
  return enabled
end

---Re-read the source list in every buffer ZCmp drives, and start any provider
---module that has arrived since. What `:ZCmp reload` runs. While disabled it
---only forgets which modules have started, so that enabling again starts them.
function M.reload()
  require('zcmp.sources').reset()
  -- Deliberately before the guard: forgetting is all reloading can mean while
  -- disabled. Attaching here would map keys and write 'complete' with every
  -- autocmd gone and nothing left to maintain them -- a state |zcmp.is_enabled()|
  -- would go on denying.
  if not enabled then
    return
  end
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
  config.add_provider(id, provider)
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
---@return lsp.ClientCapabilities
function M.get_lsp_capabilities(override)
  return require('zcmp.lsp').capabilities(override)
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
