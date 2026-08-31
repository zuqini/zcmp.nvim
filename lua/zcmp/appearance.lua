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

---A group with `reverse` carried out rather than carried over. The flag
---swaps foreground and background at draw time, so a borrowed foreground
---merged over a reversed row would be drawn as that row's *background* --
---Neovim's default `PmenuSel` sets it on both channels, which turned the
---kind column into a solid block. The swap is done here and the flag
---dropped, per channel: gui `reverse` and `cterm.reverse` are separate, and
---a row that leaves a colour unset takes `Normal`'s, as the draw would.
---@param hl table A |nvim_get_hl()| dict, freshly returned and safe to edit
---@param normal table `Normal`, for the ends a reversed group leaves open
---@return table
local function resolved(hl, normal)
  if hl.reverse then
    hl.fg, hl.bg = hl.bg or normal.bg, hl.fg or normal.fg
    hl.reverse = nil
  end
  if hl.cterm and hl.cterm.reverse then
    hl.ctermfg, hl.ctermbg = hl.ctermbg or normal.ctermbg, hl.ctermfg or normal.ctermfg
    hl.cterm.reverse = nil
  end
  return hl
end

function M.apply()
  local name = config.options.appearance.kind_hl
  if name == nil or name == false or name == '' then
    return
  end

  if vim.fn.hlexists(name) == 0 then
    vim.notify_once(
      ('zcmp: appearance.kind_hl names no highlight group: %q'):format(name),
      vim.log.levels.WARN
    )
    return
  end

  local kind = api.nvim_get_hl(0, { name = name, link = false })
  if not kind.fg and not kind.ctermfg then
    -- Cleared, or linked to nothing: hlexists() says yes to both, and to a
    -- reader the option is just not working.
    vim.notify_once(
      ('zcmp: appearance.kind_hl group %q has no foreground to borrow'):format(name),
      vim.log.levels.WARN
    )
    return
  end

  if not saved then
    saved = {}
    for _, group in ipairs(GROUPS) do
      saved[group] = api.nvim_get_hl(0, { name = group })
    end
  end

  -- The row's whole look with only the foreground swapped: attributes and
  -- both colour channels, so a reversed or bold row -- in the gui or with
  -- 'termguicolors' off -- does not carry one cell that is neither.
  local normal = api.nvim_get_hl(0, { name = 'Normal', link = false })
  local pmenu = resolved(api.nvim_get_hl(0, { name = 'Pmenu', link = false }), normal)
  local selected = api.nvim_get_hl(0, { name = 'PmenuSel', link = false })
  selected = next(selected) and resolved(selected, normal) or pmenu
  local borrowed = { fg = kind.fg, ctermfg = kind.ctermfg }
  api.nvim_set_hl(0, 'PmenuKind', vim.tbl_extend('force', pmenu, borrowed))
  api.nvim_set_hl(0, 'PmenuKindSel', vim.tbl_extend('force', selected, borrowed))
end

function M.restore()
  for group, hl in pairs(saved or {}) do
    pcall(api.nvim_set_hl, 0, group, hl)
  end
  saved = nil
end

return M
