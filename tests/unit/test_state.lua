-- Tests for review.nvim state module
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Helper to get fresh state module
local function get_state()
  package.loaded["review.core.state"] = nil
  return require("review.core.state")
end

-- Reset state before each test
T["setup"] = function()
  local state = get_state()
  state.reset()
end

-- =============================================================================
-- Initial State Tests
-- =============================================================================

T["initial state"] = MiniTest.new_set()

T["initial state"]["has correct defaults"] = function()
  local state = get_state()
  expect.equality(state.state.active, false)
  expect.equality(state.state.mode, "local")
  expect.equality(state.state.base, "HEAD")
  expect.equality(state.state.panel_open, false)
  expect.equality(#state.state.files, 0)
  expect.equality(#state.state.comments, 0)
end

T["initial state"]["pr is nil"] = function()
  local state = get_state()
  expect.equality(state.state.pr, nil)
  expect.equality(state.state.pr_mode, nil)
end

T["initial state"]["layout is empty table"] = function()
  local state = get_state()
  expect.equality(type(state.state.layout), "table")
  expect.equality(next(state.state.layout), nil)
end

-- =============================================================================
-- is_active Tests
-- =============================================================================

T["is_active"] = MiniTest.new_set()

T["is_active"]["returns false initially"] = function()
  local state = get_state()
  expect.equality(state.is_active(), false)
end

T["is_active"]["returns true when set"] = function()
  local state = get_state()
  state.state.active = true
  expect.equality(state.is_active(), true)
end

-- =============================================================================
-- reset Tests
-- =============================================================================

T["reset"] = MiniTest.new_set()

T["reset"]["resets all fields to defaults"] = function()
  local state = get_state()

  -- Modify state
  state.state.active = true
  state.state.mode = "pr"
  state.state.base = "main"
  state.state.pr = { number = 123 }
  state.state.panel_open = true
  table.insert(state.state.files, { path = "test.lua" })
  table.insert(state.state.comments, { id = "1", body = "test" })

  -- Reset
  state.reset()

  -- Verify defaults
  expect.equality(state.state.active, false)
  expect.equality(state.state.mode, "local")
  expect.equality(state.state.base, "HEAD")
  expect.equality(state.state.pr, nil)
  expect.equality(state.state.panel_open, false)
  expect.equality(#state.state.files, 0)
  expect.equality(#state.state.comments, 0)
end

-- =============================================================================
-- set_mode Tests
-- =============================================================================

T["set_mode"] = MiniTest.new_set()

T["set_mode"]["sets mode to local"] = function()
  local state = get_state()
  state.set_mode("local")
  expect.equality(state.state.mode, "local")
end

T["set_mode"]["sets mode to pr"] = function()
  local state = get_state()
  state.set_mode("pr")
  expect.equality(state.state.mode, "pr")
end

T["set_mode"]["sets base when provided"] = function()
  local state = get_state()
  state.set_mode("local", { base = "main" })
  expect.equality(state.state.base, "main")
end

T["set_mode"]["sets pr when provided"] = function()
  local state = get_state()
  local pr = { number = 123, title = "Test PR" }
  state.set_mode("pr", { pr = pr })
  expect.equality(state.state.pr.number, 123)
  expect.equality(state.state.pr.title, "Test PR")
end

T["set_mode"]["sets pr_mode when provided"] = function()
  local state = get_state()
  state.set_mode("pr", { pr_mode = "remote" })
  expect.equality(state.state.pr_mode, "remote")
end

-- =============================================================================
-- Comment Management Tests
-- =============================================================================

T["comments"] = MiniTest.new_set()

T["comments"]["add_comment adds to list"] = function()
  local state = get_state()
  state.add_comment({ id = "1", kind = "local", body = "test" })
  expect.equality(#state.state.comments, 1)
  expect.equality(state.state.comments[1].body, "test")
end

T["comments"]["find_comment finds by id"] = function()
  local state = get_state()
  state.add_comment({ id = "1", body = "first" })
  state.add_comment({ id = "2", body = "second" })

  local comment, idx = state.find_comment("2")
  expect.equality(comment.body, "second")
  expect.equality(idx, 2)
end

T["comments"]["find_comment returns nil for missing"] = function()
  local state = get_state()
  local comment, idx = state.find_comment("missing")
  expect.equality(comment, nil)
  expect.equality(idx, nil)
end

T["comments"]["remove_comment removes by id"] = function()
  local state = get_state()
  state.add_comment({ id = "1", body = "first" })
  state.add_comment({ id = "2", body = "second" })

  local success = state.remove_comment("1")
  expect.equality(success, true)
  expect.equality(#state.state.comments, 1)
  expect.equality(state.state.comments[1].id, "2")
end

T["comments"]["remove_comment returns false for missing"] = function()
  local state = get_state()
  local success = state.remove_comment("missing")
  expect.equality(success, false)
end

T["comments"]["set_comments replaces all"] = function()
  local state = get_state()
  state.add_comment({ id = "1", body = "old" })

  state.set_comments({
    { id = "2", body = "new1" },
    { id = "3", body = "new2" },
  })

  expect.equality(#state.state.comments, 2)
  expect.equality(state.state.comments[1].id, "2")
end

-- =============================================================================
-- Comment Filtering Tests
-- =============================================================================

T["get_comments_sorted"] = MiniTest.new_set()

T["get_comments_sorted"]["sorts by file then line"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", file = "b.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
    { id = "3", file = "a.lua", line = 5 },
    { id = "4", file = "b.lua", line = 1 },
  })

  local sorted = state.get_comments_sorted()
  expect.equality(sorted[1].id, "3") -- a.lua:5
  expect.equality(sorted[2].id, "2") -- a.lua:20
  expect.equality(sorted[3].id, "4") -- b.lua:1
  expect.equality(sorted[4].id, "1") -- b.lua:10
end

T["get_comments_sorted"]["excludes comments without file or line"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", kind = "conversation", body = "no file" },
    { id = "3", file = "a.lua" }, -- no line
  })

  local sorted = state.get_comments_sorted()
  expect.equality(#sorted, 1)
  expect.equality(sorted[1].id, "1")
end

T["get_comments_for_file"] = MiniTest.new_set()

T["get_comments_for_file"]["filters by file"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "b.lua", line = 20 },
    { id = "3", file = "a.lua", line = 5 },
  })

  local comments = state.get_comments_for_file("a.lua")
  expect.equality(#comments, 2)
end

T["get_comments_for_file"]["returns empty for no matches"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
  })

  local comments = state.get_comments_for_file("nonexistent.lua")
  expect.equality(#comments, 0)
end

T["get_unresolved_comments"] = MiniTest.new_set()

T["get_unresolved_comments"]["filters unresolved with file"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", file = "a.lua", resolved = false },
    { id = "2", file = "b.lua", resolved = true },
    { id = "3", file = "c.lua", resolved = false },
    { id = "4", resolved = false }, -- no file
  })

  local unresolved = state.get_unresolved_comments()
  expect.equality(#unresolved, 2)
end

T["get_pending_comments"] = MiniTest.new_set()

T["get_pending_comments"]["filters local pending"] = function()
  local state = get_state()
  state.set_comments({
    { id = "1", kind = "local", status = "pending" },
    { id = "2", kind = "local", status = "submitted" },
    { id = "3", kind = "review", status = "pending" },
    { id = "4", kind = "local", status = "pending" },
  })

  local pending = state.get_pending_comments()
  expect.equality(#pending, 2)
end

-- =============================================================================
-- File Management Tests
-- =============================================================================

T["files"] = MiniTest.new_set()

T["files"]["add_file adds to list"] = function()
  local state = get_state()
  state.add_file({ path = "test.lua", status = "modified" })
  expect.equality(#state.state.files, 1)
  expect.equality(state.state.files[1].path, "test.lua")
end

T["files"]["find_file finds by path"] = function()
  local state = get_state()
  state.add_file({ path = "a.lua" })
  state.add_file({ path = "b.lua" })

  local file, idx = state.find_file("b.lua")
  expect.equality(file.path, "b.lua")
  expect.equality(idx, 2)
end

T["files"]["find_file returns nil for missing"] = function()
  local state = get_state()
  local file, idx = state.find_file("missing.lua")
  expect.equality(file, nil)
  expect.equality(idx, nil)
end

T["files"]["set_files replaces all"] = function()
  local state = get_state()
  state.add_file({ path = "old.lua" })

  state.set_files({
    { path = "new1.lua" },
    { path = "new2.lua" },
  })

  expect.equality(#state.state.files, 2)
  expect.equality(state.state.files[1].path, "new1.lua")
end

T["files"]["set_current_file updates current"] = function()
  local state = get_state()
  state.set_current_file("test.lua")
  expect.equality(state.state.current_file, "test.lua")
end

-- =============================================================================
-- Comment Count Tests
-- =============================================================================

T["update_file_comment_counts"] = MiniTest.new_set()

T["update_file_comment_counts"]["updates counts correctly"] = function()
  local state = get_state()
  state.set_files({
    { path = "a.lua", comment_count = 0 },
    { path = "b.lua", comment_count = 0 },
  })
  state.set_comments({
    { id = "1", file = "a.lua" },
    { id = "2", file = "a.lua" },
    { id = "3", file = "b.lua" },
  })

  expect.equality(state.state.files[1].comment_count, 2)
  expect.equality(state.state.files[2].comment_count, 1)
end

T["update_file_comment_counts"]["resets counts on update"] = function()
  local state = get_state()
  state.set_files({
    { path = "a.lua", comment_count = 5 },
  })
  state.set_comments({
    { id = "1", file = "a.lua" },
  })

  expect.equality(state.state.files[1].comment_count, 1)
end

-- =============================================================================
-- Stats Tests
-- =============================================================================

T["get_stats"] = MiniTest.new_set()

T["get_stats"]["returns correct stats"] = function()
  local state = get_state()
  state.set_files({
    { path = "a.lua" },
    { path = "b.lua" },
    { path = "c.lua" },
  })
  state.set_comments({
    { id = "1", kind = "review", file = "a.lua" },
    { id = "2", kind = "local", status = "pending" },
    { id = "3", kind = "local", status = "pending" },
    { id = "4", kind = "review", file = "b.lua", resolved = false },
    { id = "5", kind = "conversation" },
  })

  local stats = state.get_stats()
  expect.equality(stats.total_files, 3)
  expect.equality(stats.total_comments, 5)
  expect.equality(stats.pending_comments, 2)
  expect.equality(stats.unresolved_comments, 1)
end

T["get_stats"]["returns zeros for empty state"] = function()
  local state = get_state()
  local stats = state.get_stats()
  expect.equality(stats.total_files, 0)
  expect.equality(stats.total_comments, 0)
  expect.equality(stats.pending_comments, 0)
  expect.equality(stats.unresolved_comments, 0)
end

return T
