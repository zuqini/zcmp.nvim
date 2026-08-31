---The commands a keymap entry names, and the functions |zcmp| re-exports.
---
---Each returns whether it did anything, which is what lets a key list fall
---through: `{ 'select_next', 'snippet_forward', 'fallback' }` tries each in
---turn until one answers true.
---
---`M`'s whole function surface IS |zcmp.keymap|'s command namespace -- see
---`resolve_command()` there. A function added to `M` becomes a bindable
---command name by that alone; a helper another module needs stays a local,
---not a field of `M`.

local api = vim.api
local config = require('zcmp.config')
local fallback = require('zcmp.fallback')

local M = {}

---Reports a raising accept callback's error, naming it rather than letting it
---propagate through zcmp's own frames as a traceback -- same voice as
---`fallback.lua`'s `report` and the snippet engine's, in
---`sources/snippets/init.lua`.
---@param err string
local function report_callback(err)
  vim.notify(('zcmp: an accept callback raised: %s'):format(tostring(err)), vim.log.levels.ERROR)
end

---Questions rather than commands. A keymap entry naming one would swallow the
---key on a truthy answer without doing anything, so |zcmp.keymap| declines
---them; everything else this module exports is a command.
M.predicates = {
  is_visible = true,
  is_menu_visible = true,
  is_snippet_active = true,
  snippet_active = true,
  is_documentation_visible = true,
  is_signature_visible = true,
}

---@param keys string
---@param opts? zcmp.fallback.FeedOpts
local function feed(keys, opts)
  fallback.press(keys, opts)
end

---Menu-state queries, asked of `fallback.lua` rather than answered here a
---second time: `needs_menu_closed()` there needs the same two questions, and
---the selection rule is load-bearing for `<CR>`/preselect behaviour on both
---sides of the edge.
local function pumvisible()
  return fallback.menu_visible()
end

local function has_selection()
  return fallback.has_selection()
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

---Scoped to the buffer the accept happens in, and to the `zcmp` augroup --
---`init.lua` creates it by that name and `zcmp.disable()` deletes it by that
---name; requiring `init.lua` back to reach it would cycle, since it requires
---this module, but `nvim_create_augroup` on the same name is idempotent, and
---`clear = false` joins the group rather than wiping the autocmds already in
---it. Not a one-shot on the first CompleteDone: `vim.lsp.completion`'s
---`trigger()` calls `vim.fn.complete()` on every server response while a
---completion is active, which fires a `discard` CompleteDone with the menu
---left up (`sources/snippets/init.lua` names the same restart) -- routine in
---zcmp's default config, and no sign this feed's own accept has landed. So a
---`discard` leaves the autocmd armed; `accept` retires it and runs the
---callback; anything else -- `cancel`, what `hide()`'s <C-e> produces --
---retires it *without* running the callback, since this feed's own <C-y>
---(|i_CTRL-Y|, no CompleteDone of its own once the menu it would have closed
---is already gone) is never coming, and leaving the arm live would spend it
---on whatever completes next in the buffer instead.
---
---`InsertLeave` alone does not bound the arm: <C-c> produces a `discard`
---CompleteDone but no InsertLeave, only a `ModeChanged` out of insert. The
---`ModeChanged` autocmd below is the backstop for exactly that gap, and all
---three are buffer-local, so wiping this arm's buffer mid-completion reaps
---all three with it rather than leaking the last one.
---@param opts? { callback?: fun() }
local function on_accept(opts)
  if not (opts and opts.callback) then
    return
  end
  local group = api.nvim_create_augroup('zcmp', { clear = false })
  local ids = {}
  local function retire()
    for _, id in ipairs(ids) do
      api.nvim_del_autocmd(id)
    end
  end
  ids[#ids + 1] = api.nvim_create_autocmd('CompleteDone', {
    group = group,
    buffer = 0,
    callback = function()
      local reason = vim.v.event.reason
      if reason == 'discard' then
        return
      end
      retire()
      if reason == 'accept' then
        local ok, err = pcall(opts.callback)
        if not ok then
          report_callback(err)
        end
      end
    end,
  })
  ids[#ids + 1] = api.nvim_create_autocmd('InsertLeave', {
    group = group,
    buffer = 0,
    callback = retire,
  })
  ids[#ids + 1] = api.nvim_create_autocmd('ModeChanged', {
    group = group,
    buffer = 0,
    -- Any transition into Normal, not just plain insert's `i:n`: <Insert>
    -- then <C-c> lands in Replace mode first, producing `i:R` then `R:n`.
    callback = function(args)
      if args.match:sub(-2) == ':n' then
        retire()
      end
    end,
  })
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
---itself; this is the manual trigger, and what `<C-space>` is bound to. The
---menu it opens obeys the same rule as one that opened by itself: nothing is
---selected unless a source marked an item, so with nothing marked <CR> opens
---a line and `select_and_accept` takes the first item.
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
  feed('<C-e>', { ends_completion = true })
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
  feed('<C-y>', { ends_completion = true })
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
  feed(has_selection() and '<C-y>' or '<C-n><C-y>', { ends_completion = true })
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
  -- Parenthesised: every command answers with one boolean, and pcall's second
  -- value would ride out of a `return cmp.hide_documentation()` in a user's own.
  return (pcall(api.nvim_win_close, win, true))
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
---|vim.lsp.buf.signature_help()|, on the key you bind it to. Declines while
---the window is already up -- through `M.` rather than a local, since
---`is_signature_visible()` is defined below this function -- so a preset
---pairing it with `hide_signature` (`['<C-k>'] = { 'show_signature',
---'hide_signature', 'fallback' }`) toggles instead of re-asking forever.
---@return boolean
function M.show_signature()
  if not config.options.signature.enabled then
    return false
  end
  if M.is_signature_visible() then
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
  return (pcall(api.nvim_win_close, vim.b.lsp_floating_preview, true))
end

---`lsp_floating_preview` is a private var set by
---|vim.lsp.util.open_floating_preview()|, undocumented in |lsp|; there is no
---public alternative today. It is set for *every* caller of that function --
---`vim.lsp.buf.hover()` and, on the 0.12.0 floor, `vim.diagnostic.open_float`
---included -- so it alone cannot tell a signature float from a hover one; a
---`show_signature`/`hide_signature` pair gated only on it would decline to
---(re)open signature help while a hover float is up, and would close that
---hover instead of leaving it alone. `open_floating_preview()` also tags the
---float's *window* with `opts.focus_id`, via `nvim_win_set_var`; `vim.lsp.buf`
---sets it to the request method, `'textDocument/hover'` for a hover float and
---`'textDocument/signatureHelp'` for this one, which is the one distinguishing
---mark between the two. Named here so a future core change that breaks either
---is diagnosable rather than a silent no-op.
---@return boolean
function M.is_signature_visible()
  local win = vim.b.lsp_floating_preview
  return type(win) == 'number'
    and api.nvim_win_is_valid(win)
    and vim.w[win]['textDocument/signatureHelp'] ~= nil
end

return M
