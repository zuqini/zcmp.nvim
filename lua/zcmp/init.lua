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

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      buffer.attach(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and sources.wants(args.buf, 'lsp') then
        require('zcmp.lsp').attach(client, args.buf)
      end
      buffer.attach(args.buf)
    end,
  })

  -- The buffer may have just lost its last completion provider, leaving 'o'
  -- with nothing to answer.
  vim.api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(args)
      buffer.attach(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = appearance.apply })
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
function M.enable()
  appearance.apply()
  buffer.apply_globals()
  autocmds()
  buffer.attach_all()
  enabled = true
end

---Hand completion back: mappings are removed, the options ZCmp set are
---restored, and buffers keep whatever 'complete' they had before.
function M.disable()
  pcall(vim.api.nvim_del_augroup_by_name, GROUP)
  buffer.detach_all()
  buffer.restore_globals()
  enabled = false
end

---@return boolean
function M.is_enabled()
  return enabled
end

---Re-read the source list everywhere, and start any provider module that has
---arrived since. What `:ZCmp reload` runs.
function M.reload()
  sources.reset()
  buffer.detach_all()
  buffer.attach_all()
end

---Register a provider. It serves nothing until a `sources.default` or
---`sources.per_filetype` list names it; see |zcmp-providers|.
---@param id string
---@param provider zcmp.Provider
function M.add_source_provider(id, provider)
  config.options.sources.providers[id] = provider
end

---Add providers to one filetype's list, on top of `sources.default`.
---@param filetype string
---@param ids string|string[]
function M.add_filetype_source(filetype, ids)
  local per_filetype = config.options.sources.per_filetype
  local list = per_filetype[filetype]
  if not list then
    list = { inherit_defaults = true }
    per_filetype[filetype] = list
  end
  ---@type string[]
  local adding = type(ids) == 'table' and ids or { ids }
  for _, id in ipairs(adding) do
    if not vim.tbl_contains(list, id) then
      list[#list + 1] = id
    end
  end
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
