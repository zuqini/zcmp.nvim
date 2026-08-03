---:checkhealth zcmp — diagnostics for a ZCmp setup.
---
---Answers the questions a menu that came back empty raises: is the engine
---there, is this buffer one ZCmp drives, which sources answered for it, and is
---something else driving completion too. Discovered automatically by
---`:checkhealth zcmp` — nothing registers it.

local buffer = require('zcmp.buffer')
local keymap = require('zcmp.keymap')
local sources = require('zcmp.sources')

local M = {}

local ISSUES_URL = 'https://github.com/zuqini/zcmp.nvim/issues'

local MINIMAL_CONFIG = "require('zcmp').setup()"

---Engines that also write 'complete', map insert mode or call complete().
local RIVALS = {
  ['blink.cmp'] = 'blink.cmp',
  ['cmp'] = 'nvim-cmp',
  ['mini.completion'] = 'mini.completion',
}

local function check_environment()
  vim.health.start('Environment')

  vim.health.info('zcmp ' .. require('zcmp').version)

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
end

local function check_setup()
  vim.health.start('Setup')

  if require('zcmp').is_enabled() then
    vim.health.ok('enabled')
  else
    vim.health.warn('not enabled — nothing has taken over completion', {
      MINIMAL_CONFIG,
    })
  end

  local expected = buffer.completeopt()
  if vim.o.completeopt == expected then
    vim.health.ok("'completeopt' = " .. vim.o.completeopt)
  else
    vim.health.warn(("'completeopt' is %q, not the %q this config asks for"):format(vim.o.completeopt, expected), {
      'Something set it after zcmp did. The menu still works; selection and',
      'the documentation popup may not behave as configured.',
    })
  end

  vim.health.info(("'autocompletedelay' = %d"):format(vim.o.autocompletedelay))

  -- The flag is newer than the 0.12.0 floor, and without it nothing is ever
  -- selected while the menu opens by itself.
  if require('zcmp.config').options.completion.list.selection.preselect and not buffer.can_preselect() then
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
    vim.health.error('no sources — `sources.default` is empty')
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
    vim.health.warn('zcmp is not attached here', {
      ('buftype is %q; the `enabled` option decides which buffers zcmp drives.'):format(vim.bo[bufnr].buftype),
    })
    return
  end

  vim.health.ok(("'complete' = %s"):format(vim.bo[bufnr].complete))
  if vim.bo[bufnr].autocomplete then
    vim.health.ok("'autocomplete' is on")
  else
    vim.health.info("'autocomplete' is off — the menu opens on the key bound to `show`")
  end

  local keys = {}
  for _, key in ipairs(keymap.installed(bufnr)) do
    keys[#keys + 1] = key.lhs
  end
  if #keys == 0 then
    vim.health.warn('no keys mapped — `keymap.preset` is "none" and nothing was added')
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
---buffer is the one it was called from.
---@return integer
local function subject()
  local alternate = vim.fn.bufnr('#')
  if alternate ~= -1 and vim.api.nvim_buf_is_valid(alternate) and vim.bo[alternate].buftype == '' then
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
