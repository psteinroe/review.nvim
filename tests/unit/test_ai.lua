-- Tests for review.nvim AI integration
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset state and config before each test
      package.loaded["review.integrations.ai"] = nil
      package.loaded["review.config"] = nil
      package.loaded["review.core.state"] = nil

      local config = require("review.config")
      config.setup()

      local state = require("review.core.state")
      state.reset()
    end,
    post_case = function()
      -- Clean up
    end,
  },
})

-- ============================================================================
-- Provider Registration Tests
-- ============================================================================
T["providers"] = MiniTest.new_set()

T["providers"]["has clipboard provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.clipboard), "table")
  expect.equality(ai.providers.clipboard.name, "Clipboard")
end

T["providers"]["clipboard is always available"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.providers.clipboard.check(), true)
end

T["providers"]["has opencode provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.opencode), "table")
  expect.equality(ai.providers.opencode.name, "OpenCode")
end

T["providers"]["has claude provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.claude), "table")
  expect.equality(ai.providers.claude.name, "Claude Code")
end

T["providers"]["has codex provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.codex), "table")
  expect.equality(ai.providers.codex.name, "Codex CLI")
end

T["providers"]["has aider provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.aider), "table")
  expect.equality(ai.providers.aider.name, "Aider")
end

T["providers"]["has avante provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.avante), "table")
  expect.equality(ai.providers.avante.name, "Avante")
end

T["providers"]["has custom provider"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(type(ai.providers.custom), "table")
  expect.equality(ai.providers.custom.name, "Custom")
end

T["providers"]["custom provider unavailable without handler"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.providers.custom.check(), false)
end

T["providers"]["custom provider available with handler"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      custom_handler = function() end,
    },
  })

  local ai = require("review.integrations.ai")
  expect.equality(ai.providers.custom.check(), true)
end

-- ============================================================================
-- Provider Registration/Unregistration Tests
-- ============================================================================
T["register"] = MiniTest.new_set()

T["register"]["can register custom provider"] = function()
  local ai = require("review.integrations.ai")

  ai.register_provider("test_provider", {
    name = "Test Provider",
    description = "A test provider",
    check = function()
      return true
    end,
    send = function() end,
  })

  expect.equality(type(ai.providers.test_provider), "table")
  expect.equality(ai.providers.test_provider.name, "Test Provider")
  expect.equality(ai.providers.test_provider.check(), true)
end

T["register"]["can unregister provider"] = function()
  local ai = require("review.integrations.ai")

  ai.register_provider("to_remove", {
    name = "To Remove",
    description = "Will be removed",
    check = function()
      return true
    end,
    send = function() end,
  })

  expect.equality(type(ai.providers.to_remove), "table")

  ai.unregister_provider("to_remove")
  expect.equality(ai.providers.to_remove, nil)
end

-- ============================================================================
-- get_provider Tests
-- ============================================================================
T["get_provider"] = MiniTest.new_set()

T["get_provider"]["returns clipboard as fallback"] = function()
  local ai = require("review.integrations.ai")

  -- Mock all providers as unavailable except clipboard
  local original_checks = {}
  for name, provider in pairs(ai.providers) do
    original_checks[name] = provider.check
    if name ~= "clipboard" then
      provider.check = function()
        return false
      end
    end
  end

  local provider, name = ai.get_provider()

  -- Restore
  for n, check in pairs(original_checks) do
    ai.providers[n].check = check
  end

  expect.equality(name, "clipboard")
  expect.equality(provider.name, "Clipboard")
end

T["get_provider"]["respects explicit provider config"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      provider = "clipboard",
    },
  })

  local ai = require("review.integrations.ai")
  local provider, name = ai.get_provider()

  expect.equality(name, "clipboard")
end

T["get_provider"]["falls back to auto if configured provider unavailable"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      provider = "nonexistent",
    },
  })

  local ai = require("review.integrations.ai")

  -- This will fall back since "nonexistent" doesn't exist
  local provider, name = ai.get_provider()
  expect.equality(type(provider), "table")
end

-- ============================================================================
-- get_available_providers Tests
-- ============================================================================
T["get_available_providers"] = MiniTest.new_set()

T["get_available_providers"]["returns list of providers"] = function()
  local ai = require("review.integrations.ai")
  local providers = ai.get_available_providers()

  expect.equality(type(providers), "table")
  expect.equality(#providers > 0, true)
end

T["get_available_providers"]["includes clipboard as available"] = function()
  local ai = require("review.integrations.ai")
  local providers = ai.get_available_providers()

  local found = false
  for _, p in ipairs(providers) do
    if p.name == "clipboard" then
      found = true
      expect.equality(p.available, true)
    end
  end
  expect.equality(found, true)
end

T["get_available_providers"]["returns sorted by name"] = function()
  local ai = require("review.integrations.ai")
  local providers = ai.get_available_providers()

  local names = {}
  for _, p in ipairs(providers) do
    table.insert(names, p.name)
  end

  local sorted = vim.deepcopy(names)
  table.sort(sorted)

  expect.equality(names, sorted)
end

-- ============================================================================
-- get_type_label Tests
-- ============================================================================
T["get_type_label"] = MiniTest.new_set()

T["get_type_label"]["returns NOTE for note type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label("note"), "NOTE")
end

T["get_type_label"]["returns ISSUE for issue type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label("issue"), "ISSUE")
end

T["get_type_label"]["returns SUGGESTION for suggestion type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label("suggestion"), "SUGGESTION")
end

T["get_type_label"]["returns PRAISE for praise type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label("praise"), "PRAISE")
end

T["get_type_label"]["returns COMMENT for nil type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label(nil), "COMMENT")
end

T["get_type_label"]["returns COMMENT for unknown type"] = function()
  local ai = require("review.integrations.ai")
  expect.equality(ai.get_type_label("unknown"), "COMMENT")
end

-- ============================================================================
-- escape_for_shell Tests
-- ============================================================================
T["escape_for_shell"] = MiniTest.new_set()

T["escape_for_shell"]["escapes single quotes"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.escape_for_shell("it's a test")
  expect.equality(result, "it'\\''s a test")
end

T["escape_for_shell"]["handles multiple quotes"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.escape_for_shell("it's Bob's test")
  expect.equality(result, "it'\\''s Bob'\\''s test")
end

T["escape_for_shell"]["returns unchanged string without quotes"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.escape_for_shell("no quotes here")
  expect.equality(result, "no quotes here")
end

-- ============================================================================
-- build_prompt Tests
-- ============================================================================
T["build_prompt"] = MiniTest.new_set()

T["build_prompt"]["returns string"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()
  expect.equality(type(prompt), "string")
end

T["build_prompt"]["includes Code Review header"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()
  expect.equality(prompt:find("# Code Review") ~= nil, true)
end

T["build_prompt"]["includes Instructions section"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()
  expect.equality(prompt:find("## Instructions") ~= nil, true)
end

T["build_prompt"]["includes Changes section when include_diff is true"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = true })
  expect.equality(prompt:find("## Changes") ~= nil, true)
end

T["build_prompt"]["excludes Changes section when include_diff is false"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })
  expect.equality(prompt:find("## Changes"), nil)
end

T["build_prompt"]["excludes Instructions when include_instructions is false"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_instructions = false })
  expect.equality(prompt:find("## Instructions"), nil)
end

T["build_prompt"]["includes PR info when PR is set"] = function()
  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = {
    number = 123,
    title = "Test PR",
    author = "testuser",
    branch = "feature",
    base = "main",
    description = "Test description",
  }

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("## PR Information") ~= nil, true)
  expect.equality(prompt:find("PR #123") ~= nil, true)
  expect.equality(prompt:find("Test PR") ~= nil, true)
  expect.equality(prompt:find("@testuser") ~= nil, true)
end

T["build_prompt"]["includes pending comments"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test1",
    kind = "local",
    body = "Fix this issue",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    file = "test.lua",
    line = 10,
    type = "issue",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("## Review Comments") ~= nil, true)
  expect.equality(prompt:find("Fix this issue") ~= nil, true)
  expect.equality(prompt:find("%[ISSUE%]") ~= nil, true)
end

T["build_prompt"]["excludes submitted comments"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test1",
    kind = "local",
    body = "Already submitted",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    file = "test.lua",
    line = 10,
    type = "note",
    status = "submitted",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Already submitted"), nil)
end

T["build_prompt"]["uses custom instructions when configured"] = function()
  local config = require("review.config")
  config.setup({
    ai = {
      instructions = "Custom instruction text here",
    },
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Custom instruction text here") ~= nil, true)
end

T["build_prompt"]["includes default instructions when not configured"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("Please review the code changes") ~= nil, true)
end

T["build_prompt"]["formats multiple comments with numbers"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test1",
    kind = "local",
    body = "First comment",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    file = "test.lua",
    line = 10,
    type = "note",
    status = "pending",
  })
  state.add_comment({
    id = "test2",
    kind = "local",
    body = "Second comment",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    file = "test.lua",
    line = 20,
    type = "issue",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("1%. %*%*%[NOTE%]%*%*") ~= nil, true)
  expect.equality(prompt:find("2%. %*%*%[ISSUE%]%*%*") ~= nil, true)
end

-- ============================================================================
-- send_to_clipboard Tests
-- ============================================================================
T["send_to_clipboard"] = MiniTest.new_set()

T["send_to_clipboard"]["copies prompt to plus register"] = function()
  vim.fn.setreg("+", "")

  local ai = require("review.integrations.ai")
  ai.send_to_clipboard()

  local content = vim.fn.getreg("+")
  expect.equality(content:find("# Code Review") ~= nil, true)
end

T["send_to_clipboard"]["copies prompt to star register"] = function()
  vim.fn.setreg("*", "")

  local ai = require("review.integrations.ai")
  ai.send_to_clipboard()

  local content = vim.fn.getreg("*")
  expect.equality(content:find("# Code Review") ~= nil, true)
end

-- ============================================================================
-- clipboard provider send Tests
-- ============================================================================
T["clipboard_send"] = MiniTest.new_set()

T["clipboard_send"]["copies to clipboard"] = function()
  vim.fn.setreg("+", "")
  vim.fn.setreg("*", "")

  local ai = require("review.integrations.ai")
  ai.providers.clipboard.send("test prompt content", {})

  expect.equality(vim.fn.getreg("+"), "test prompt content")
  expect.equality(vim.fn.getreg("*"), "test prompt content")
end

-- ============================================================================
-- Provider check function Tests
-- ============================================================================
T["provider_checks"] = MiniTest.new_set()

T["provider_checks"]["opencode check uses executable"] = function()
  local ai = require("review.integrations.ai")
  -- Just verify it returns a boolean
  local result = ai.providers.opencode.check()
  expect.equality(type(result), "boolean")
end

T["provider_checks"]["claude check uses executable"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.providers.claude.check()
  expect.equality(type(result), "boolean")
end

T["provider_checks"]["codex check uses executable"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.providers.codex.check()
  expect.equality(type(result), "boolean")
end

T["provider_checks"]["aider check uses executable"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.providers.aider.check()
  expect.equality(type(result), "boolean")
end

T["provider_checks"]["avante check uses pcall"] = function()
  local ai = require("review.integrations.ai")
  local result = ai.providers.avante.check()
  expect.equality(type(result), "boolean")
end

-- ============================================================================
-- Edge Cases Tests
-- ============================================================================
T["edge_cases"] = MiniTest.new_set()

T["edge_cases"]["build_prompt handles empty state"] = function()
  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt()
  expect.equality(type(prompt), "string")
  expect.equality(#prompt > 0, true)
end

T["edge_cases"]["build_prompt handles PR without description"] = function()
  local state = require("review.core.state")
  state.state.mode = "pr"
  state.state.pr = {
    number = 123,
    title = "Test PR",
    author = "testuser",
    branch = "feature",
    base = "main",
    description = "",
  }

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  expect.equality(prompt:find("### Description"), nil)
end

T["edge_cases"]["build_prompt handles comment without file"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test1",
    kind = "local",
    body = "General comment",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not crash and should include the comment
  expect.equality(prompt:find("General comment") ~= nil, true)
end

T["edge_cases"]["build_prompt handles comment with file but no line"] = function()
  local state = require("review.core.state")
  state.add_comment({
    id = "test1",
    kind = "local",
    body = "File comment",
    author = "you",
    created_at = "2024-01-01T00:00:00Z",
    file = "test.lua",
    type = "note",
    status = "pending",
  })

  local ai = require("review.integrations.ai")
  local prompt = ai.build_prompt({ include_diff = false })

  -- Should not crash
  expect.equality(prompt:find("File comment") ~= nil, true)
end

return T
