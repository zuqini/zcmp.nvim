local helpers = require('helpers')
local lsp = require('zcmp.lsp')

---An in-process language server that answers completion, so that the LSP hook
---can be exercised without a binary to talk to.
---@param dispatchers vim.lsp.rpc.Dispatchers
local function server(dispatchers)
  local closing = false
  return {
    request = function(method, _, callback)
      if method == 'initialize' then
        callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '.' } } } })
      elseif method == 'shutdown' then
        callback(nil, nil)
      end
      return true, 1
    end,
    notify = function(method)
      if method == 'exit' then
        dispatchers.on_exit(0, 15)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
      dispatchers.on_exit(0, 15)
    end,
  }
end

---@param bufnr integer
---@return vim.lsp.Client
local function start(bufnr)
  local id = assert(vim.lsp.start({ name = 'zcmp-test', cmd = server }, { bufnr = bufnr }))
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
  end)
  return assert(vim.lsp.get_client_by_id(id))
end

local function stop()
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop()
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients() == 0
  end)
end

before_each(helpers.reset)
after_each(function()
  stop()
  helpers.cleanup()
end)

describe('trigger characters', function()
  it('widens the list to every letter, so a plain keyword re-asks', function()
    local client = { server_capabilities = { completionProvider = { triggerCharacters = { '.', ':' } } } }

    local chars = lsp.trigger_characters(client)
    assert.contains(chars, '.')
    assert.contains(chars, ':')
    assert.contains(chars, 'a')
    assert.contains(chars, 'Z')
  end)

  -- setup() runs again on every LspAttach, and a server may re-announce.
  it('is idempotent', function()
    local client = { server_capabilities = { completionProvider = { triggerCharacters = { 'a', '.' } } } }

    client.server_capabilities.completionProvider.triggerCharacters = lsp.trigger_characters(client)
    local twice = lsp.trigger_characters(client)

    assert.are.equal(53, #twice)
  end)

  it('copes with a server that declares none', function()
    local client = { server_capabilities = { completionProvider = {} } }

    assert.are.equal(52, #lsp.trigger_characters(client))
  end)
end)

describe('capabilities', function()
  it("are core's, with an override merged in", function()
    local capabilities = lsp.capabilities({ textDocument = { completion = { dynamicRegistration = true } } })

    assert.is_true(capabilities.textDocument.completion.dynamicRegistration)
    assert.is_not_nil(capabilities.textDocument.hover)
  end)
end)

describe('attaching a client', function()
  it('declines a server that does not complete', function()
    local client = {
      server_capabilities = {},
      supports_method = function()
        return false
      end,
    }

    assert.is_false(lsp.attach(client, 0))
  end)

  it('reports no server to ask in a buffer with none', function()
    assert.is_false(lsp.available(helpers.buffer()))
  end)

  it('wires a real client up, and puts the omnifunc in complete', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)
    vim.wait(500, function()
      return vim.bo[bufnr].complete:find('o,', 1, true) ~= nil
    end)

    assert.is_true(lsp.available(bufnr))
    assert.are.equal('o,.^100,w^100,b^100', vim.bo[bufnr].complete)
    assert.contains(client.server_capabilities.completionProvider.triggerCharacters, 'a')
    -- Set by vim.lsp.completion.enable(), and the whole of what the 'o' flag
    -- has to call.
    assert.are_not.equal('', vim.bo[bufnr].omnifunc)
  end)

  it('leaves the omnifunc out again once the last client goes', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'lsp', 'buffer' } } })

    start(bufnr)
    vim.wait(500, function()
      return vim.bo[bufnr].complete:find('o,', 1, true) ~= nil
    end)

    stop()
    vim.wait(500, function()
      return vim.bo[bufnr].complete == '.^100,w^100,b^100'
    end)
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)

  it('leaves a client alone when the source list does not name lsp', function()
    local bufnr = helpers.buffer()
    vim.api.nvim_set_current_buf(bufnr)
    require('zcmp').setup({ sources = { default = { 'buffer' } } })

    local client = start(bufnr)
    helpers.settle(bufnr)

    assert.are.same({ '.' }, client.server_capabilities.completionProvider.triggerCharacters)
    assert.are.equal('.^100,w^100,b^100', vim.bo[bufnr].complete)
  end)
end)
