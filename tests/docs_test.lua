---The default configuration is written out three times: `DEFAULTS` in
---`config.lua`, the block under "Configuration" in README.md, and the one under
---|zcmp.setup()| in doc/zcmp.txt. Only discipline kept them in step, and a
---default a user copies out of the README and then gets different behaviour
---from is the worst kind of documentation bug -- it reads as the option not
---working.
---
---Both blocks are run as the Lua they claim to be, against a `require` that
---catches what they hand `setup()`. So a block that stops parsing fails here
---too, which is the other thing worth knowing about a config in a README.

local config = require('zcmp.config')
local helpers = require('helpers')

local ROOT = vim.fn.getcwd()

---Providers have a section of their own on every surface, and both blocks
---abbreviate them to `{}` on purpose.
local ABBREVIATED = 'sources%.providers%.'

---@param path string
---@return string[]
local function lines(path)
  local full = ROOT .. '/' .. path
  assert.are.equal(1, vim.fn.filereadable(full), ('%s is not readable from %s'):format(path, ROOT))
  return vim.fn.readfile(full)
end

---The lines of the first `opens`..`closes` block after `anchor`.
---@param path string
---@param anchor string
---@param opens string
---@param closes string
---@return string
local function block(path, anchor, opens, closes)
  local found, inside, collected = false, false, {}
  for _, line in ipairs(lines(path)) do
    if not found then
      found = line:match(anchor) ~= nil
    elseif not inside then
      inside = line:match(opens) ~= nil
    elseif line:match(closes) then
      return table.concat(collected, '\n')
    else
      collected[#collected + 1] = line
    end
  end
  error(('no %s block after %q in %s'):format(opens, anchor, path))
end

---What the block would hand `setup()`, by running it against a `require` of
---our own. The `vim.*` calls it shows are inside function bodies, so nothing
---in this table is ever called.
---@param source string
---@return table
local function documented(source)
  local chunk = assert(loadstring(source, 'documented config'))
  local captured
  setfenv(chunk, {
    vim = vim,
    require = function()
      return {
        setup = function(opts)
          captured = opts
        end,
      }
    end,
  })
  chunk()
  -- Parenthesised: assert() answers with everything it was handed, and the
  -- message would arrive as this function's second return value.
  return (assert(captured, 'the documented config never reached setup()'))
end

---Every value that is not a table or a function, by its dotted path.
---@param value table
---@param prefix? string
---@param out? table<string, any>
---@return table<string, any>
local function leaves(value, prefix, out)
  out = out or {}
  prefix = prefix or ''
  for key, item in pairs(value) do
    local path = prefix == '' and tostring(key) or ('%s.%s'):format(prefix, tostring(key))
    if type(item) == 'table' then
      leaves(item, path, out)
    elseif type(item) ~= 'function' then
      out[path] = item
    end
  end
  return out
end

local SURFACES = {
  { name = 'README.md', anchor = '^## Configuration', opens = '^```lua', closes = '^```' },
  { name = 'doc/zcmp.txt', anchor = '^zcmp%.setup', opens = '^>lua', closes = '^<' },
}

before_each(helpers.reset)
after_each(helpers.cleanup)

describe('the documented defaults', function()
  for _, surface in ipairs(SURFACES) do
    it(('in %s are the defaults'):format(surface.name), function()
      local shown = leaves(documented(block(surface.name, surface.anchor, surface.opens, surface.closes)))
      local defaults = leaves(config.options)

      for path, value in pairs(shown) do
        assert.are.equal(
          defaults[path],
          value,
          ('%s documents %s = %s; config.lua has %s'):format(
            surface.name,
            path,
            vim.inspect(value),
            vim.inspect(defaults[path])
          )
        )
      end
    end)

    it(('in %s leave no default out'):format(surface.name), function()
      local shown = leaves(documented(block(surface.name, surface.anchor, surface.opens, surface.closes)))

      for path in pairs(leaves(config.options)) do
        if not path:match(ABBREVIATED) then
          assert.is_not_nil(shown[path], ('%s does not document %s'):format(surface.name, path))
        end
      end
    end)
  end
end)

-- Vim help has no emphasis syntax: `*word*` defines a tag, and one already
-- defined -- elsewhere, or twice in this file -- fails `:helptags`, which
-- lazy.nvim runs on every install. Four commits in a row left one behind.
describe('doc/zcmp.txt', function()
  it('defines only tags of its own, and builds', function()
    local dir = helpers.tempdir()
    vim.fn.writefile(lines('doc/zcmp.txt'), dir .. '/zcmp.txt')

    vim.cmd.helptags(dir)

    for _, entry in ipairs(vim.fn.readfile(dir .. '/tags')) do
      local tag = entry:match('^([^\t]+)')
      assert.is_truthy(tag:lower():match('^:?zcmp'), ('doc/zcmp.txt defines a tag that is not its own: %s'):format(tag))
    end
  end)
end)
