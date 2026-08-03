---The `:ZCmp` user command. Created by |zcmp.setup()|.

local M = {}

local SUBCOMMANDS = { 'status', 'enable', 'disable', 'reload' }

---What is actually serving this buffer, which is the question a menu that came
---back empty raises: the source is either not in the list, not available here,
---or its module is not installed.
---@param bufnr integer
---@return string[]
function M.status(bufnr)
  local zcmp = require('zcmp')
  local buffer = require('zcmp.buffer')
  local keymap = require('zcmp.keymap')

  local lines = {
    ('ZCmp.nvim %s — %s'):format(zcmp.version, zcmp.is_enabled() and 'enabled' or 'disabled'),
    ('buffer %d — %s'):format(bufnr, buffer.attached(bufnr) and 'attached' or 'not attached'),
    '',
    'sources',
  }

  for _, source in ipairs(require('zcmp.sources').list(bufnr)) do
    local entries = table.concat(source.entries, ',')
    -- A provider can serve its flags and still have a problem worth naming --
    -- a module of its own that is not installed.
    local detail = source.problem and (entries ~= '' and source.problem .. ' — ' .. entries or source.problem)
      or entries
    lines[#lines + 1] = ('  %-10s %s %s'):format(source.id, source.active and '✓' or '✗', detail)
  end

  local keys = {}
  for _, key in ipairs(keymap.installed(bufnr)) do
    keys[#keys + 1] = ('%s:%s'):format(key.mode, key.lhs)
  end

  vim.list_extend(lines, {
    '',
    ("'complete'   %s"):format(vim.bo[bufnr].complete),
    ("'completeopt' %s"):format(vim.o.completeopt),
    ("'autocomplete' %s"):format(vim.bo[bufnr].autocomplete),
    '',
    'keys  ' .. (#keys > 0 and table.concat(keys, ' ') or '(none)'),
  })
  return lines
end

local ACTIONS = {
  status = function()
    vim.api.nvim_echo({ { table.concat(M.status(vim.api.nvim_get_current_buf()), '\n') } }, false, {})
  end,
  enable = function()
    require('zcmp').enable()
  end,
  disable = function()
    require('zcmp').disable()
  end,
  reload = function()
    require('zcmp').reload()
  end,
}

---Take the command back out. |zcmp.disable()| deliberately leaves it, since
---`:ZCmp enable` is how you come back; used by tests.
function M.remove()
  pcall(vim.api.nvim_del_user_command, 'ZCmp')
end

function M.create()
  vim.api.nvim_create_user_command('ZCmp', function(args)
    local action = ACTIONS[args.args ~= '' and args.args or 'status']
    if not action then
      vim.notify(('zcmp: unknown subcommand %q'):format(args.args), vim.log.levels.ERROR)
      return
    end
    action()
  end, {
    nargs = '?',
    desc = 'zcmp: report, enable, disable or reload completion',
    complete = function(lead)
      return vim.tbl_filter(function(name)
        return vim.startswith(name, lead)
      end, SUBCOMMANDS)
    end,
  })
end

return M
