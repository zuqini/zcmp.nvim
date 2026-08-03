---The one highlight ZCmp sets.
---
---Core draws the kind column in |hl-PmenuKind|, which most colorschemes leave
---linked to Pmenu -- so the column reads as part of the label. This colours it
---from `appearance.kind_hl` while keeping the menu's own background, including
---the selected row's.

local api = vim.api
local config = require('zcmp.config')

local M = {}

function M.apply()
  local name = config.options.appearance.kind_hl
  if not name or name == '' then
    return
  end

  local kind = api.nvim_get_hl(0, { name = name, link = false })
  if not kind.fg then
    return
  end

  local pmenu = api.nvim_get_hl(0, { name = 'Pmenu', link = false })
  local selected = api.nvim_get_hl(0, { name = 'PmenuSel', link = false })
  api.nvim_set_hl(0, 'PmenuKind', { fg = kind.fg, bg = pmenu.bg })
  api.nvim_set_hl(0, 'PmenuKindSel', { fg = kind.fg, bg = selected.bg or pmenu.bg })
end

return M
