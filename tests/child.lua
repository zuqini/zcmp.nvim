---Driving a real Neovim through real keystrokes, from the test suite.
---
---Insert-mode completion cannot be exercised in-process. `nvim -l` has no main
---loop, so `nvim_feedkeys(..., 'n')` queues keys nothing ever reads; and the
---'x' flag runs them in a nested exec, where textlock forbids the |complete()|
---call that is the whole point. A child Neovim started with `-c` has a main
---loop, which is the only place the completion menu is real.
---
---The child runs a fragment that calls `scenario()` and then `done()`.
---Whatever it emitted comes back here as a table.

local M = {}

---Injected above the fragment. `scenario` is the shape every case here needs:
---put the buffer in a known state, type, let the menu settle, then send what
---accepts or dismisses it.
local PRELUDE = [[
vim.opt.runtimepath:prepend(%q)
local OUT = %q
local results = {}
local finished = false

local function emit(key, value)
  results[key] = value
end

local function done()
  if finished then return end
  finished = true
  vim.fn.writefile({ vim.json.encode(results) }, OUT)
  vim.cmd('qa!')
end

-- A child that hangs would hang the suite; this is the backstop.
vim.defer_fn(done, 20000)

local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function offered()
  local words = {}
  for _, item in ipairs(vim.fn.complete_info({ 'items' }).items or {}) do
    words[#words + 1] = item.word
  end
  return words
end

-- 'm' and not 'n': a key that is not remapped never reaches the mappings
-- under test, and would just insert itself.
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'mt', false)
end

---Each step: { name, lines?, cursor?, keys, delay?, then_keys? }. Emitted
---under `name` as { offered, lines } -- what the menu held after `keys`, and
---what the buffer held once `then_keys` had been sent.
local function scenario(steps, after)
  local index = 0
  local function next_step()
    index = index + 1
    local step = steps[index]
    if not step then return after() end

    feed('<Esc>')
    vim.defer_fn(function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, step.lines or { '' })
      vim.api.nvim_win_set_cursor(0, step.cursor or { 1, 0 })
      feed(step.keys)
      vim.defer_fn(function()
        local result = { offered = offered() }
        feed((step.then_keys or '') .. '<Esc>')
        vim.defer_fn(function()
          result.lines = lines()
          emit(step.name, result)
          next_step()
        end, 300)
      end, step.delay or 600)
    end, 150)
  end
  vim.defer_fn(next_step, 300)
end
]]

---@param fragment string Lua source; must call `done()` when it is finished
---@param root string Repository root, prepended to the child's runtimepath
---@param tempdir string Somewhere to leave the script and its output
---@return table results
---@return string log Whatever the child wrote to stderr
function M.run(fragment, root, tempdir)
  local script = tempdir .. '/child_script.lua'
  local out = tempdir .. '/child_out.json'
  vim.fn.writefile(vim.split(PRELUDE:format(root, out) .. fragment, '\n'), script)

  local result = vim
    .system({ vim.v.progpath, '--headless', '-u', 'NONE', '-c', 'luafile ' .. script }, {
      text = true,
      timeout = 60000,
    })
    :wait()

  local written = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out)[1] or nil
  if not written then
    return {}, (result.stderr or '') .. (result.stdout or '')
  end
  local ok, decoded = pcall(vim.json.decode, written)
  return ok and decoded or {}, result.stderr or ''
end

return M
