---The commands a keymap entry names, and the functions |zcmp| re-exports.
---
---Each returns whether it did anything, which is what lets a key list fall
---through: `{ 'select_next', 'snippet_forward', 'fallback' }` tries each in
---turn until one answers true.

local api = vim.api
local config = require('zcmp.config')

local M = {}

---A key is being translated into other keys, so they go in front of whatever
---is already queued -- the 'i' flag. Without it a mapping fed from a macro or
---from |feedkeys()| lands after the rest of the sequence.
---@param keys string
local function feed(keys)
  api.nvim_feedkeys(vim.keycode(keys), 'in', false)
end

local function pumvisible()
  return vim.fn.pumvisible() == 1
end

local function has_selection()
  return pumvisible() and vim.fn.complete_info({ 'selected' }).selected >= 0
end

local function inserting()
  return vim.fn.mode() == 'i'
end

local function selecting()
  return vim.list_contains({ 's', 'S', '\19' }, vim.fn.mode())
end

local function snippets()
  return config.options.snippets
end

---@param opts? { callback?: fun() }
local function on_accept(opts)
  if opts and opts.callback then
    api.nvim_create_autocmd('CompleteDone', { once = true, callback = opts.callback })
  end
end

---The info window cannot be focused -- reaching it means leaving insert mode,
---which dismisses the menu. complete_info() takes no 'what' filter here: the
---filter silently drops 'preview_winid'.
---@return integer?
local function info_win()
  local win = vim.fn.complete_info().preview_winid
  return win and win ~= 0 and api.nvim_win_is_valid(win) and win or nil
end

---@param keys string
---@return boolean
local function scroll(keys)
  local win = info_win()
  if not win then
    return false
  end
  api.nvim_win_call(win, function()
    vim.cmd('normal! ' .. vim.keycode(keys))
  end)
  return true
end

---@return boolean
function M.is_visible()
  return pumvisible()
end

M.is_menu_visible = M.is_visible

---Open the completion menu. With `completion.menu.auto_show` on it opens by
---itself; this is the manual trigger, and what `<C-space>` is bound to.
---@return boolean
function M.show()
  if pumvisible() or not inserting() then
    return false
  end
  feed('<C-n>')
  return true
end

---|zcmp.show()|, but only when a keyword run precedes the cursor -- so a
---`<Tab>` bound to it still indents at the start of a line. ZCmp's own; blink
---has no equivalent because its menu opens with no delay.
---@return boolean
function M.show_on_keyword()
  if pumvisible() or not inserting() then
    return false
  end
  local before = api.nvim_get_current_line():sub(1, api.nvim_win_get_cursor(0)[2])
  if vim.fn.matchstr(before, '\\k*$') == '' then
    return false
  end
  feed('<C-n>')
  return true
end

---Close the menu, restoring the text as typed.
---@return boolean
function M.hide()
  if not pumvisible() then
    return false
  end
  feed('<C-e>')
  return true
end

M.cancel = M.hide

---@return boolean
function M.select_next()
  if not pumvisible() then
    return false
  end
  feed('<C-n>')
  return true
end

---@return boolean
function M.select_prev()
  if not pumvisible() then
    return false
  end
  feed('<C-p>')
  return true
end

---Accept the selected item. Nothing selected means nothing to accept, which is
---what leaves `<CR>` free to open a line.
---@param opts? { callback?: fun() }
---@return boolean
function M.accept(opts)
  if not has_selection() then
    return false
  end
  feed('<C-y>')
  on_accept(opts)
  return true
end

---Accept the selected item, selecting the first one if none is.
---@param opts? { callback?: fun() }
---@return boolean
function M.select_and_accept(opts)
  if not pumvisible() then
    return false
  end
  feed(has_selection() and '<C-y>' or '<C-n><C-y>')
  on_accept(opts)
  return true
end

---@return boolean
function M.snippet_forward()
  if not snippets().active({ direction = 1 }) then
    return false
  end
  snippets().jump(1)
  return true
end

---@return boolean
function M.snippet_backward()
  if not snippets().active({ direction = -1 }) then
    return false
  end
  snippets().jump(-1)
  return true
end

---Delete the placeholder under the cursor and keep typing in its place. ZCmp's
---own: Select mode otherwise leaves you in Normal mode afterwards.
---@return boolean
function M.snippet_delete()
  if not selecting() or not snippets().active() then
    return false
  end
  feed('<C-o>s')
  return true
end

---@param filter? vim.snippet.ActiveFilter
---@return boolean
function M.is_snippet_active(filter)
  return snippets().active(filter)
end

M.snippet_active = M.is_snippet_active

---@return boolean
function M.is_documentation_visible()
  return info_win() ~= nil
end

---Core opens the documentation popup together with the menu, and offers no way
---to ask for it afterwards -- `completion.documentation.auto_show` is the whole
---switch. Kept so a blink keymap moves over unedited; it always falls through.
---@return boolean
function M.show_documentation()
  return false
end

---@return boolean
function M.hide_documentation()
  local win = info_win()
  if not win then
    return false
  end
  return pcall(api.nvim_win_close, win, true)
end

---@param count? integer Lines; a half page by default
---@return boolean
function M.scroll_documentation_down(count)
  return scroll(count and (count .. '<C-e>') or '<C-d>')
end

---@param count? integer Lines; a half page by default
---@return boolean
function M.scroll_documentation_up(count)
  return scroll(count and (count .. '<C-y>') or '<C-u>')
end

---Ask for signature help, if `signature.enabled` is set. ZCmp never asks by
---itself: the window that follows you through an argument list is core's
---|vim.lsp.buf.signature_help()|, on the key you bind it to.
---@return boolean
function M.show_signature()
  if not config.options.signature.enabled then
    return false
  end
  if not next(vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/signatureHelp' })) then
    return false
  end
  vim.lsp.buf.signature_help()
  return true
end

---@return boolean
function M.hide_signature()
  if not M.is_signature_visible() then
    return false
  end
  return pcall(api.nvim_win_close, vim.b.lsp_floating_preview, true)
end

---@return boolean
function M.is_signature_visible()
  local win = vim.b.lsp_floating_preview
  return type(win) == 'number' and api.nvim_win_is_valid(win)
end

return M
