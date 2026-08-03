---The one highlight ZCmp sets.
---
---Core draws the kind column in |hl-PmenuKind|, which most colorschemes leave
---linked to Pmenu -- so the column reads as part of the label. This colours it
---from `appearance.kind_hl` while keeping the menu's own background, including
---the selected row's.

local api = vim.api
local config = require('zcmp.config')

local M = {}

local GROUPS = { 'PmenuKind', 'PmenuKindSel' }

---The two groups as they were before ZCmp wrote over them, so that
---|zcmp.disable()| hands them back with the rest. Captured as a link where
---they were a link, which is what a colourscheme usually leaves them as.
---@type table<string, vim.api.keyset.get_hl_info>?
local saved = nil

function M.apply()
  local name = config.options.appearance.kind_hl
  if name == nil or name == false or name == '' then
    return
  end
  if type(name) ~= 'string' then
    vim.notify_once(
      ('zcmp: appearance.kind_hl is a highlight group or false, not %s'):format(vim.inspect(name)),
      vim.log.levels.WARN
    )
    return
  end

  local kind = api.nvim_get_hl(0, { name = name, link = false })
  if not kind.fg then
    return
  end

  if not saved then
    saved = {}
    for _, group in ipairs(GROUPS) do
      saved[group] = api.nvim_get_hl(0, { name = group })
    end
  end

  local pmenu = api.nvim_get_hl(0, { name = 'Pmenu', link = false })
  local selected = api.nvim_get_hl(0, { name = 'PmenuSel', link = false })
  api.nvim_set_hl(0, 'PmenuKind', { fg = kind.fg, bg = pmenu.bg })
  api.nvim_set_hl(0, 'PmenuKindSel', { fg = kind.fg, bg = selected.bg or pmenu.bg })
end

---A colourscheme has just redefined every group, so what was captured belongs
---to the one before it.
function M.forget()
  saved = nil
end

function M.restore()
  for group, hl in pairs(saved or {}) do
    pcall(api.nvim_set_hl, 0, group, hl)
  end
  saved = nil
end

return M
