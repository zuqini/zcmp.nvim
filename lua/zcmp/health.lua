---:checkhealth zcmp — diagnostics for a ZCmp setup.
---
---Answers the questions a menu that came back empty raises: is the engine
---there, is this buffer one ZCmp drives, which sources answered for it, and is
---something else driving completion too. Discovered automatically by
---`:checkhealth zcmp` — nothing registers it.

local buffer = require('zcmp.buffer')
local config = require('zcmp.config')
local keymap = require('zcmp.keymap')
local lsp = require('zcmp.lsp')
local sources = require('zcmp.sources')
local zcmp = require('zcmp')

local M = {}

local ISSUES_URL = 'https://github.com/zuqini/zcmp.nvim/issues'

local MINIMAL_CONFIG = "require('zcmp').setup()"

---Shared by both 'completeopt' mismatch warnings -- global-slot, in
---check_setup(), and local-slot, in check_buffer(). Only the diagnosis (why
---it does not match) differs between them; what it costs does not.
local COMPLETEOPT_CONSEQUENCE = {
  'The menu still works; selection and the documentation popup may not',
  'behave as configured.',
}

---What un-disables completion, for whichever section needs to say so.
---`:ZCmp` exists only once `setup()` has run and created it, which is what
---tells "never set up" (the command itself is missing) apart from "set up,
---then `:ZCmp disable`" (the command is there and is the fix). `:ZCmp`
---existing is a proxy for "setup() has run" -- owned by commands.lua and
---init.lua -- so if the command ever moves to `plugin/zcmp.lua` (created
---unconditionally, before any `setup()` call), this check must change with
---it.
---@return string
local function remedy()
  if vim.fn.exists(':ZCmp') == 2 then
    return ':ZCmp enable'
  end
  return MINIMAL_CONFIG
end

---Engines that also write 'complete', map insert mode or call complete().
local RIVALS = {
  ['blink.cmp'] = 'blink.cmp',
  ['cmp'] = 'nvim-cmp',
  ['mini.completion'] = 'mini.completion',
}

local function check_environment()
  vim.health.start('Environment')

  vim.health.info('zcmp ' .. zcmp.version)

  if vim.fn.has('nvim-0.12') == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()) .. ' (>= 0.12.0 required)')
  else
    vim.health.error('Neovim 0.12.0+ is required')
  end

  if vim.fn.exists('&autocomplete') == 1 then
    vim.health.ok("'autocomplete' is available — the menu can open as you type")
  else
    vim.health.error("'autocomplete' is missing — this Neovim cannot open the menu by itself")
  end

  if type(vim.lsp.completion) == 'table' then
    vim.health.ok('vim.lsp.completion is available')
  else
    vim.health.warn('vim.lsp.completion is missing — the LSP source cannot autotrigger')
  end
  if type(vim.tbl_get(vim.lsp, 'completion', 'get')) ~= 'function' then
    -- The one call `lsp.retrigger()` makes; without it the server is asked
    -- once per menu, which is the gap `retrigger` exists to close.
    vim.health.warn('vim.lsp.completion.get() is missing — the LSP source cannot be asked again as you type', {
      'Set sources.providers.lsp.opts.retrigger = false to stop trying.',
    })
  end
end

local function check_setup()
  vim.health.start('Setup')

  local enabled = zcmp.is_enabled()
  if enabled then
    vim.health.ok('enabled')
  else
    vim.health.warn('not enabled — nothing has taken over completion', {
      remedy(),
    })
  end

  -- Not enabled means zcmp never set 'completeopt', so comparing it here
  -- would blame zcmp for a value it had no part in; the warning above already
  -- covers that case.
  if enabled then
    local expected = buffer.completeopt()
    -- 'completeopt' is global-local; vim.o reads the effective value for
    -- whichever buffer is current, which here is checkhealth's own scratch
    -- buffer. apply_globals() writes the global slot, so that is what to
    -- compare against.
    if vim.go.completeopt == expected then
      vim.health.ok("'completeopt' = " .. vim.go.completeopt)
    else
      vim.health.warn(
        ("'completeopt' is %q, not the %q this config asks for"):format(vim.go.completeopt, expected),
        vim.list_extend({ 'Something set it after zcmp did.' }, COMPLETEOPT_CONSEQUENCE)
      )
    end
  end

  -- Checked rather than reported, and only while enabled -- for the same
  -- reason 'completeopt' is. A non-zero value is the one that hides every
  -- non-LSP source behind vim.lsp.completion's autotrigger; see
  -- buffer.apply_globals().
  if enabled then
    if vim.go.autocompletedelay == 0 then
      vim.health.ok("'autocompletedelay' = 0")
    else
      vim.health.warn(("'autocompletedelay' is %d, not the 0 zcmp sets"):format(vim.go.autocompletedelay), {
        'Something set it after zcmp did. While it is non-zero, the LSP',
        "autotrigger opens the menu before any 'complete' source is scanned,",
        'and no source but the server reaches that menu until you delete a',
        'character. Set `completion.menu.auto_show = false` to stop the menu',
        'opening as you type instead.',
      })
    end
  end

  -- The flag is newer than the 0.12.0 floor, and without it nothing is ever
  -- selected while the menu opens by itself.
  if config.options.completion.list.selection.preselect and not buffer.can_preselect() then
    vim.health.warn("this Neovim has no `preselect` in 'completeopt'", {
      'Nothing is selected while `completion.menu.auto_show` is on, so a key',
      'bound to `accept` never fires. Bind `select_and_accept` instead, or',
      'update to a Neovim that has the flag.',
    })
  end
end

local function check_sources(bufnr)
  vim.health.start('Sources')

  local resolved = sources.list(bufnr)
  if #resolved == 0 then
    local _, filetype = sources.ids(bufnr)
    if not filetype then
      vim.health.error('no sources — `sources.default` is empty')
    else
      vim.health.info(('no sources — `sources.per_filetype.%s` is empty'):format(filetype))
    end
    return
  end

  for _, source in ipairs(resolved) do
    local name = source.provider.name or source.id
    -- A provider declaring both `flags` and a `module` serves the flags even
    -- when the module is missing. Reporting that as a plain tick hides the one
    -- thing checkhealth is here to find.
    if source.active and source.problem then
      vim.health.warn(('%s: %s — serving %s'):format(name, source.problem, table.concat(source.entries, ',')))
    elseif source.active then
      vim.health.ok(('%s: %s'):format(name, table.concat(source.entries, ',')))
    elseif source.problem == sources.UNAVAILABLE then
      vim.health.info(('%s: nothing to serve in this buffer'):format(name))
    else
      vim.health.warn(('%s: %s'):format(name, source.problem or 'contributes nothing'))
    end
  end
end

local function check_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  vim.health.start(('Buffer %d%s'):format(bufnr, name ~= '' and ' — ' .. vim.fn.fnamemodify(name, ':~:.') or ''))

  if not buffer.attached(bufnr) then
    local hint
    if not zcmp.is_enabled() then
      hint = ('zcmp is disabled -- `%s`'):format(remedy())
    else
      hint = ("the `enabled` option answered false here (buftype %q), or an earlier pass reported an error")
        :format(vim.bo[bufnr].buftype)
    end
    vim.health.warn('zcmp is not attached here', { hint })
    return
  end

  vim.health.ok(("'complete' = %s"):format(vim.bo[bufnr].complete))
  if vim.bo[bufnr].autocomplete then
    vim.health.ok("'autocomplete' is on")
  else
    vim.health.info("'autocomplete' is off — the menu opens on the key bound to `show`")
  end

  -- Only where there is something to ask again: a buffer with no
  -- completion-capable client has nothing this hook would ever reach for.
  if lsp.available(bufnr) then
    if lsp.retriggering(bufnr) then
      vim.health.ok('asking the LSP source again as you type')
    else
      vim.health.warn('not asking the LSP source again as you type', {
        "Either `lsp` is not in this buffer's source list, its `enabled`",
        'predicate answered false, `sources.providers.lsp.opts.retrigger` is',
        'false, or it has not finished attaching yet.',
      })
    end
  end

  -- 'completeopt' is global-local: check_setup() compares the global slot,
  -- and says nothing about a `setlocal completeopt` sitting in this one.
  -- vim.bo[bufnr] reads the raw local value, empty when none is set.
  local local_completeopt = vim.bo[bufnr].completeopt
  if local_completeopt ~= '' and local_completeopt ~= buffer.completeopt() then
    vim.health.warn(
      ("'completeopt' is set locally to %q, not this config's %q"):format(local_completeopt, buffer.completeopt()),
      vim.list_extend({
        -- zcmp never writes the local slot -- a ftplugin or an autocmd's
        -- `setlocal` reached this buffer before zcmp attached, not after.
        ':setlocal completeopt< drops the local value; or set it to match.',
      }, COMPLETEOPT_CONSEQUENCE)
    )
  end

  local keys = {}
  for _, key in ipairs(keymap.installed(bufnr)) do
    keys[#keys + 1] = key.lhs
  end
  if #keys == 0 then
    vim.health.warn('no keys mapped — every entry is empty, or `keymap.preset` is "none"')
  else
    vim.health.info('keys: ' .. table.concat(keys, ' '))
  end
end

---Two engines both writing 'complete', mapping <Tab> and calling complete() is
---the one failure that looks like every other failure.
local function check_conflicts()
  vim.health.start('Other completion engines')

  local loaded = {}
  for module, name in pairs(RIVALS) do
    if package.loaded[module] then
      loaded[#loaded + 1] = name
    end
  end

  if #loaded == 0 then
    vim.health.ok('none loaded')
    return
  end
  vim.health.warn(('also loaded: %s'):format(table.concat(loaded, ', ')), {
    'Two engines will fight over the menu and over insert-mode mappings.',
    'Load one.',
  })
end

local function check_bug_report()
  vim.health.start('Reporting a bug')
  vim.health.info(table.concat({
    'Reproduce with a minimal config, then open an issue at',
    ISSUES_URL .. ' including:',
    '  - the minimal config below (edited to trigger the bug)',
    '  - the full :checkhealth zcmp output (it carries both versions)',
    '  - the `:ZCmp status` output for the buffer it happens in',
    '',
    'Minimal config — save as repro.lua, run with: nvim -u repro.lua',
    '',
    MINIMAL_CONFIG,
  }, '\n'))
end

---`:checkhealth` runs the check inside its own `nofile` buffer, which zcmp
---never drives -- reporting on that one would warn every time. The alternate
---buffer is the one it was called from, reported whenever it is a valid
---buffer at all: gating on `buffer.attached()` would fall back to the
---checkhealth scratch buffer in exactly the not-attached cases (disabled,
---excluded by a custom `enabled`, a buftype `check_buffer()` warns about)
---that this check exists to explain.
---@return integer
local function subject()
  local alternate = vim.fn.bufnr('#')
  if alternate ~= -1 and vim.api.nvim_buf_is_valid(alternate) then
    return alternate
  end
  return vim.api.nvim_get_current_buf()
end

---Entry point for `:checkhealth zcmp`.
---@param bufnr? integer Defaults to the buffer checkhealth was called from
function M.check(bufnr)
  bufnr = bufnr or subject()
  check_environment()
  -- Every section below reads an option that arrived with the floor, and an
  -- unknown option raises rather than answering nil: the run would abort and
  -- take the one line explaining why down with it.
  if vim.fn.has('nvim-0.12') == 0 then
    return
  end
  check_setup()
  check_sources(bufnr)
  check_buffer(bufnr)
  check_conflicts()
  check_bug_report()
end

return M
