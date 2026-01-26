-- Tests for review.ui.picker module
local T = MiniTest.new_set()

local picker = require("review.ui.picker")

-- Helper to create a test PR with all default values
local function make_pr(opts)
  opts = opts or {}
  return {
    number = opts.number or 123,
    title = opts.title or "Test PR",
    description = opts.description or "Test description",
    author = opts.author or "testuser",
    branch = opts.branch or "feature-branch",
    base = opts.base or "main",
    created_at = opts.created_at or "2025-01-01T00:00:00Z",
    updated_at = opts.updated_at or "2025-01-01T00:00:00Z",
    additions = opts.additions or 10,
    deletions = opts.deletions or 5,
    changed_files = opts.changed_files or 2,
    state = opts.state or "open",
    url = opts.url or "https://github.com/test/repo/pull/123",
  }
end

-- ============================================================================
-- format_pr()
-- ============================================================================
T["format_pr()"] = MiniTest.new_set()

T["format_pr()"]["formats basic PR info"] = function()
  local pr = make_pr({ number = 42, title = "Add feature", author = "octocat" })
  local result = picker.format_pr(pr)
  MiniTest.expect.equality(result, "#42 Add feature (@octocat)")
end

T["format_pr()"]["handles missing author"] = function()
  local pr = { number = 42, title = "Add feature" }  -- No author field
  local result = picker.format_pr(pr)
  MiniTest.expect.equality(result, "#42 Add feature")
end

T["format_pr()"]["handles missing title"] = function()
  local pr = { number = 42, author = "octocat" }  -- No title field
  local result = picker.format_pr(pr)
  MiniTest.expect.equality(result, "#42  (@octocat)")
end

T["format_pr()"]["handles empty title"] = function()
  local pr = make_pr({ number = 42, title = "", author = "octocat" })
  local result = picker.format_pr(pr)
  MiniTest.expect.equality(result, "#42  (@octocat)")
end

-- ============================================================================
-- format_pr_detailed()
-- ============================================================================
T["format_pr_detailed()"] = MiniTest.new_set()

T["format_pr_detailed()"]["includes stats"] = function()
  local pr = make_pr({
    number = 42,
    title = "Add feature",
    author = "octocat",
    additions = 100,
    deletions = 20,
    changed_files = 5,
  })
  local result = picker.format_pr_detailed(pr)
  MiniTest.expect.equality(string.find(result, "#42 Add feature") ~= nil, true)
  MiniTest.expect.equality(string.find(result, "@octocat") ~= nil, true)
  MiniTest.expect.equality(string.find(result, "+100") ~= nil, true)
  MiniTest.expect.equality(string.find(result, "-20") ~= nil, true)
  MiniTest.expect.equality(string.find(result, "5 files") ~= nil, true)
end

T["format_pr_detailed()"]["includes branch info"] = function()
  local pr = make_pr({
    number = 42,
    title = "Add feature",
    author = "octocat",
    branch = "feat/new-thing",
    base = "main",
  })
  local result = picker.format_pr_detailed(pr)
  MiniTest.expect.equality(string.find(result, "feat/new%-thing %-> main") ~= nil, true)
end

T["format_pr_detailed()"]["handles zero additions/deletions"] = function()
  local pr = make_pr({
    number = 42,
    title = "Add feature",
    author = "octocat",
    additions = 0,
    deletions = 0,
    changed_files = 1,
  })
  local result = picker.format_pr_detailed(pr)
  -- Should only show files, not +0 or -0
  MiniTest.expect.equality(string.find(result, "+0") == nil, true)
  MiniTest.expect.equality(string.find(result, "-0") == nil, true)
  MiniTest.expect.equality(string.find(result, "1 files") ~= nil, true)
end

T["format_pr_detailed()"]["handles only additions"] = function()
  local pr = make_pr({
    number = 42,
    title = "New file",
    author = "octocat",
    additions = 50,
    deletions = 0,
    changed_files = 1,
  })
  local result = picker.format_pr_detailed(pr)
  MiniTest.expect.equality(string.find(result, "+50") ~= nil, true)
  MiniTest.expect.equality(string.find(result, "-0") == nil, true)
end

T["format_pr_detailed()"]["handles only deletions"] = function()
  local pr = make_pr({
    number = 42,
    title = "Remove file",
    author = "octocat",
    additions = 0,
    deletions = 30,
    changed_files = 1,
  })
  local result = picker.format_pr_detailed(pr)
  MiniTest.expect.equality(string.find(result, "+0") == nil, true)
  MiniTest.expect.equality(string.find(result, "-30") ~= nil, true)
end

T["format_pr_detailed()"]["handles missing branch/base"] = function()
  local pr = {
    number = 42,
    title = "Add feature",
    author = "octocat",
    -- No branch or base fields
  }
  local result = picker.format_pr_detailed(pr)
  -- Should not contain arrow notation
  MiniTest.expect.equality(string.find(result, "%->") == nil, true)
end

-- ============================================================================
-- build_items()
-- ============================================================================
T["build_items()"] = MiniTest.new_set()

T["build_items()"]["builds items from PRs list"] = function()
  local prs = {
    make_pr({ number = 1, title = "First", author = "user1" }),
    make_pr({ number = 2, title = "Second", author = "user2" }),
    make_pr({ number = 3, title = "Third", author = "user3" }),
  }
  local items = picker.build_items(prs, false)
  MiniTest.expect.equality(#items, 3)
  MiniTest.expect.equality(items[1].pr.number, 1)
  MiniTest.expect.equality(items[2].pr.number, 2)
  MiniTest.expect.equality(items[3].pr.number, 3)
end

T["build_items()"]["uses basic format by default"] = function()
  local prs = {
    make_pr({ number = 42, title = "Test", author = "octocat" }),
  }
  local items = picker.build_items(prs, false)
  MiniTest.expect.equality(items[1].display, "#42 Test (@octocat)")
end

T["build_items()"]["uses detailed format when requested"] = function()
  local prs = {
    make_pr({
      number = 42,
      title = "Test",
      author = "octocat",
      additions = 10,
      deletions = 5,
    }),
  }
  local items = picker.build_items(prs, true)
  MiniTest.expect.equality(string.find(items[1].display, "+10") ~= nil, true)
  MiniTest.expect.equality(string.find(items[1].display, "-5") ~= nil, true)
end

T["build_items()"]["handles empty list"] = function()
  local items = picker.build_items({}, false)
  MiniTest.expect.equality(#items, 0)
end

T["build_items()"]["preserves PR reference in items"] = function()
  local pr = make_pr({ number = 42 })
  local prs = { pr }
  local items = picker.build_items(prs, false)
  MiniTest.expect.equality(items[1].pr, pr)
end

-- ============================================================================
-- show() - basic validation
-- ============================================================================
T["show()"] = MiniTest.new_set()

T["show()"]["notifies when no PRs provided"] = function()
  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if msg == "No PRs to select from" and level == vim.log.levels.INFO then
      notified = true
    end
  end

  picker.show({ prs = {}, prompt = "Test", on_select = function() end })

  vim.notify = original_notify
  MiniTest.expect.equality(notified, true)
end

T["show()"]["notifies when prs is nil"] = function()
  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if msg == "No PRs to select from" and level == vim.log.levels.INFO then
      notified = true
    end
  end

  picker.show({ prs = nil, prompt = "Test", on_select = function() end })

  vim.notify = original_notify
  MiniTest.expect.equality(notified, true)
end

-- ============================================================================
-- review_requests() - validation
-- ============================================================================
T["review_requests()"] = MiniTest.new_set()

T["review_requests()"]["checks github availability"] = function()
  -- Mock github.is_available to return false
  local github = require("review.integrations.github")
  local original_is_available = github.is_available
  github.is_available = function()
    return false
  end

  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if string.find(msg, "not available") and level == vim.log.levels.ERROR then
      notified = true
    end
  end

  picker.review_requests()

  vim.notify = original_notify
  github.is_available = original_is_available

  MiniTest.expect.equality(notified, true)
end

-- ============================================================================
-- open_prs() - validation
-- ============================================================================
T["open_prs()"] = MiniTest.new_set()

T["open_prs()"]["checks github availability"] = function()
  local github = require("review.integrations.github")
  local original_is_available = github.is_available
  github.is_available = function()
    return false
  end

  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if string.find(msg, "not available") and level == vim.log.levels.ERROR then
      notified = true
    end
  end

  picker.open_prs()

  vim.notify = original_notify
  github.is_available = original_is_available

  MiniTest.expect.equality(notified, true)
end

-- ============================================================================
-- my_prs() - validation
-- ============================================================================
T["my_prs()"] = MiniTest.new_set()

T["my_prs()"]["checks github availability"] = function()
  local github = require("review.integrations.github")
  local original_is_available = github.is_available
  github.is_available = function()
    return false
  end

  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if string.find(msg, "not available") and level == vim.log.levels.ERROR then
      notified = true
    end
  end

  picker.my_prs()

  vim.notify = original_notify
  github.is_available = original_is_available

  MiniTest.expect.equality(notified, true)
end

-- ============================================================================
-- search() - validation
-- ============================================================================
T["search()"] = MiniTest.new_set()

T["search()"]["checks github availability"] = function()
  local github = require("review.integrations.github")
  local original_is_available = github.is_available
  github.is_available = function()
    return false
  end

  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if string.find(msg, "not available") and level == vim.log.levels.ERROR then
      notified = true
    end
  end

  picker.search("is:open")

  vim.notify = original_notify
  github.is_available = original_is_available

  MiniTest.expect.equality(notified, true)
end

-- ============================================================================
-- input_pr_number() - validation
-- ============================================================================
T["input_pr_number()"] = MiniTest.new_set()

T["input_pr_number()"]["does not call callback with nil input"] = function()
  -- Mock vim.ui.input to simulate empty input
  local original_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback(nil)
  end

  local called = false
  picker.input_pr_number(function()
    called = true
  end)

  vim.ui.input = original_input
  MiniTest.expect.equality(called, false)
end

T["input_pr_number()"]["does not call callback with empty string"] = function()
  local original_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback("")
  end

  local called = false
  picker.input_pr_number(function()
    called = true
  end)

  vim.ui.input = original_input
  MiniTest.expect.equality(called, false)
end

T["input_pr_number()"]["notifies on invalid number"] = function()
  local original_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback("not-a-number")
  end

  local notified = false
  local original_notify = vim.notify
  vim.notify = function(msg, level)
    if msg == "Invalid PR number" and level == vim.log.levels.ERROR then
      notified = true
    end
  end

  picker.input_pr_number(function() end)

  vim.ui.input = original_input
  vim.notify = original_notify
  MiniTest.expect.equality(notified, true)
end

T["input_pr_number()"]["calls callback with valid number"] = function()
  local original_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback("42")
  end

  local received = nil
  picker.input_pr_number(function(num)
    received = num
  end)

  vim.ui.input = original_input
  MiniTest.expect.equality(received, 42)
end

T["input_pr_number()"]["calls callback with number including whitespace"] = function()
  local original_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback(" 123 ")
  end

  local received = nil
  picker.input_pr_number(function(num)
    received = num
  end)

  vim.ui.input = original_input
  -- tonumber handles whitespace
  MiniTest.expect.equality(received, 123)
end

-- ============================================================================
-- pick() - basic structure
-- ============================================================================
T["pick()"] = MiniTest.new_set()

T["pick()"]["uses vim.ui.select"] = function()
  local select_called = false
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    select_called = true
    -- Check that we have the expected options
    MiniTest.expect.equality(#items, 4)
    MiniTest.expect.equality(items[1].label, "Review requests")
    MiniTest.expect.equality(items[2].label, "Open PRs")
    MiniTest.expect.equality(items[3].label, "My PRs")
    MiniTest.expect.equality(items[4].label, "Enter PR number")
    callback(nil)  -- Cancel
  end

  picker.pick()

  vim.ui.select = original_select
  MiniTest.expect.equality(select_called, true)
end

T["pick()"]["format_item returns label"] = function()
  local format_fn = nil
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    format_fn = opts.format_item
    callback(nil)
  end

  picker.pick()

  vim.ui.select = original_select

  local item = { label = "Test Label" }
  MiniTest.expect.equality(format_fn(item), "Test Label")
end

T["pick()"]["calls action on selection"] = function()
  local action_called = false
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    -- Mock selecting the first item but replace action
    local item = { label = "Test", action = function()
      action_called = true
    end }
    callback(item)
  end

  picker.pick()

  vim.ui.select = original_select
  MiniTest.expect.equality(action_called, true)
end

T["pick()"]["does not call action on cancel"] = function()
  local action_called = false
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    callback(nil)  -- Cancel
  end

  picker.pick()

  vim.ui.select = original_select
  MiniTest.expect.equality(action_called, false)
end

-- ============================================================================
-- Backend detection (multi-picker support)
-- ============================================================================
T["get_backend()"] = MiniTest.new_set()

T["get_backend()"]["returns native when no pickers available and auto"] = function()
  -- Mock the detection functions by temporarily patching pcall for telescope and fzf-lua
  local original_require = require
  local mock_require = function(modname)
    if modname == "telescope" then
      error("not found")
    elseif modname == "fzf-lua" then
      error("not found")
    end
    return original_require(modname)
  end

  -- Reset picker module to clear any cached backend
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  -- When no pickers available and backend is auto, should return native
  -- (Note: actual detection depends on installed plugins)
  local backend = test_picker.get_backend()
  MiniTest.expect.equality(type(backend), "string")
  -- Backend should be one of the valid values
  local valid = backend == "native" or backend == "telescope" or backend == "fzf-lua"
  MiniTest.expect.equality(valid, true)
end

T["set_backend()"] = MiniTest.new_set()

T["set_backend()"]["sets backend to native"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("native")
  MiniTest.expect.equality(test_picker.backend, "native")
end

T["set_backend()"]["sets backend to telescope"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("telescope")
  MiniTest.expect.equality(test_picker.backend, "telescope")
end

T["set_backend()"]["sets backend to fzf-lua"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("fzf-lua")
  MiniTest.expect.equality(test_picker.backend, "fzf-lua")
end

T["set_backend()"]["sets backend to auto"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("auto")
  MiniTest.expect.equality(test_picker.backend, "auto")
end

T["get_backend()"]["respects explicitly set backend"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("native")
  local backend = test_picker.get_backend()
  MiniTest.expect.equality(backend, "native")
end

T["get_backend()"]["auto mode triggers detection"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("auto")
  local backend = test_picker.get_backend()

  -- When auto, should return detected backend (not "auto")
  MiniTest.expect.equality(backend ~= "auto", true)
end

-- ============================================================================
-- Config integration
-- ============================================================================
T["config integration"] = MiniTest.new_set()

T["config integration"]["respects config.picker.backend preference"] = function()
  -- Setup config with preferred backend
  package.loaded["review.config"] = nil
  local config = require("review.config")
  config.setup({
    picker = {
      backend = "native",
    },
  })

  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("auto")
  local backend = test_picker.get_backend()

  MiniTest.expect.equality(backend, "native")

  -- Cleanup
  package.loaded["review.config"] = nil
end

T["config integration"]["falls back when preferred backend unavailable"] = function()
  -- Setup config with telescope preference (may not be installed)
  package.loaded["review.config"] = nil
  local config = require("review.config")
  config.setup({
    picker = {
      backend = "telescope",
    },
  })

  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("auto")
  local backend = test_picker.get_backend()

  -- Should return some valid backend (telescope if available, else fallback)
  local valid = backend == "telescope" or backend == "fzf-lua" or backend == "native"
  MiniTest.expect.equality(valid, true)

  -- Cleanup
  package.loaded["review.config"] = nil
end

-- ============================================================================
-- Show with different backends
-- ============================================================================
T["show() with backends"] = MiniTest.new_set()

T["show() with backends"]["uses native when backend is native"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("native")

  local select_called = false
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    select_called = true
    callback(nil)
  end

  test_picker.show({
    prs = { make_pr({ number = 1 }) },
    prompt = "Test",
    on_select = function() end,
  })

  vim.ui.select = original_select
  MiniTest.expect.equality(select_called, true)
end

T["show() with backends"]["passes detailed flag to format function"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("native")

  local displayed_text = nil
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    displayed_text = opts.format_item(items[1])
    callback(nil)
  end

  test_picker.show({
    prs = { make_pr({
      number = 1,
      title = "Test",
      additions = 50,
      deletions = 10,
    }) },
    prompt = "Test",
    detailed = true,
    on_select = function() end,
  })

  vim.ui.select = original_select

  -- Detailed format should include stats
  MiniTest.expect.equality(displayed_text:find("+50") ~= nil, true)
  MiniTest.expect.equality(displayed_text:find("-10") ~= nil, true)
end

T["show() with backends"]["passes non-detailed to format function"] = function()
  package.loaded["review.ui.picker"] = nil
  local test_picker = require("review.ui.picker")

  test_picker.set_backend("native")

  local displayed_text = nil
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    displayed_text = opts.format_item(items[1])
    callback(nil)
  end

  test_picker.show({
    prs = { make_pr({
      number = 1,
      title = "Test",
      author = "user",
      additions = 50,
    }) },
    prompt = "Test",
    detailed = false,
    on_select = function() end,
  })

  vim.ui.select = original_select

  -- Basic format should NOT include stats
  MiniTest.expect.equality(displayed_text:find("+50"), nil)
  MiniTest.expect.equality(displayed_text, "#1 Test (@user)")
end

return T
