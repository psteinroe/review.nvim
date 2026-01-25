-- Tests for review.nvim navigation module
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Helper to get fresh modules
local function get_state()
  package.loaded["review.core.state"] = nil
  return require("review.core.state")
end

local function get_navigation()
  package.loaded["review.core.navigation"] = nil
  return require("review.core.navigation")
end

-- Reset state before each test
T["setup"] = function()
  local state = get_state()
  state.reset()
  -- Suppress vim.notify messages during tests
  vim.notify = function() end
end

-- =============================================================================
-- Comment Navigation Tests
-- =============================================================================

T["next_comment"] = MiniTest.new_set()

T["next_comment"]["does nothing with no comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true

  -- Should not error with no comments
  nav.next_comment()
  expect.equality(state.state.current_comment_idx, nil)
end

T["next_comment"]["goes to first comment from start"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10, body = "comment 1" },
    { id = "2", file = "a.lua", line = 20, body = "comment 2" },
  })

  nav.next_comment()
  expect.equality(state.state.current_comment_idx, 1)
end

T["next_comment"]["cycles through comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
  })

  state.state.current_comment_idx = 1
  nav.next_comment()
  expect.equality(state.state.current_comment_idx, 2)
end

T["next_comment"]["wraps around to first"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
  })

  state.state.current_comment_idx = 2
  nav.next_comment()
  expect.equality(state.state.current_comment_idx, 1)
end

T["prev_comment"] = MiniTest.new_set()

T["prev_comment"]["does nothing with no comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true

  nav.prev_comment()
  expect.equality(state.state.current_comment_idx, nil)
end

T["prev_comment"]["goes to last comment from start"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
  })

  nav.prev_comment()
  expect.equality(state.state.current_comment_idx, 2)
end

T["prev_comment"]["cycles backwards through comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
  })

  state.state.current_comment_idx = 2
  nav.prev_comment()
  expect.equality(state.state.current_comment_idx, 1)
end

T["prev_comment"]["wraps around to last"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
  })

  state.state.current_comment_idx = 1
  nav.prev_comment()
  expect.equality(state.state.current_comment_idx, 2)
end

-- =============================================================================
-- Unresolved Comment Navigation Tests
-- =============================================================================

T["next_unresolved"] = MiniTest.new_set()

T["next_unresolved"]["does nothing with no unresolved"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10, resolved = true },
  })

  nav.next_unresolved()
  -- Should not crash
end

T["next_unresolved"]["finds unresolved comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10, resolved = true },
    { id = "2", file = "a.lua", line = 20, resolved = false },
    { id = "3", file = "b.lua", line = 5, resolved = false },
  })

  local unresolved = state.get_unresolved_comments()
  expect.equality(#unresolved, 2)
end

T["prev_unresolved"] = MiniTest.new_set()

T["prev_unresolved"]["does nothing with no unresolved"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", file = "a.lua", line = 10, resolved = true },
  })

  nav.prev_unresolved()
  -- Should not crash
end

-- =============================================================================
-- Pending Comment Navigation Tests
-- =============================================================================

T["next_pending"] = MiniTest.new_set()

T["next_pending"]["does nothing with no pending"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", kind = "review", file = "a.lua", line = 10 },
  })

  nav.next_pending()
  -- Should not crash
end

T["next_pending"]["finds pending comments"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", kind = "local", status = "pending", file = "a.lua", line = 10 },
    { id = "2", kind = "local", status = "submitted", file = "a.lua", line = 20 },
    { id = "3", kind = "local", status = "pending", file = "b.lua", line = 5 },
  })

  local pending = state.get_pending_comments()
  expect.equality(#pending, 2)
end

T["prev_pending"] = MiniTest.new_set()

T["prev_pending"]["does nothing with no pending"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_comments({
    { id = "1", kind = "local", status = "submitted", file = "a.lua", line = 10 },
  })

  nav.prev_pending()
  -- Should not crash
end

-- =============================================================================
-- goto_comment Tests
-- =============================================================================

T["goto_comment"] = MiniTest.new_set()

T["goto_comment"]["does nothing with nil comment"] = function()
  local nav = get_navigation()
  -- Should not error
  nav.goto_comment(nil)
end

T["goto_comment"]["sets current_comment_idx when provided"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true

  local comment = { id = "1", file = "a.lua", line = 10, body = "test" }
  nav.goto_comment(comment, 5)

  expect.equality(state.state.current_comment_idx, 5)
end

-- =============================================================================
-- Comment at Cursor Tests
-- =============================================================================

T["get_comment_at_cursor"] = MiniTest.new_set()

T["get_comment_at_cursor"]["returns nil with no current file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = nil

  local result = nav.get_comment_at_cursor()
  expect.equality(result, nil)
end

T["get_comments_at_cursor"] = MiniTest.new_set()

T["get_comments_at_cursor"]["returns empty with no current file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = nil

  local result = nav.get_comments_at_cursor()
  expect.equality(#result, 0)
end

T["get_comments_at_cursor"]["filters by line"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = "test.lua"
  state.set_comments({
    { id = "1", file = "test.lua", line = 10, body = "at line 10" },
    { id = "2", file = "test.lua", line = 20, body = "at line 20" },
    { id = "3", file = "test.lua", line = 10, body = "also at line 10" },
    { id = "4", file = "other.lua", line = 10, body = "different file" },
  })

  -- Mock cursor at line 10
  local original_get_cursor = vim.api.nvim_win_get_cursor
  vim.api.nvim_win_get_cursor = function() return { 10, 0 } end

  local result = nav.get_comments_at_cursor()
  expect.equality(#result, 2)

  vim.api.nvim_win_get_cursor = original_get_cursor
end

-- =============================================================================
-- Hunk Navigation Tests
-- =============================================================================

T["next_hunk"] = MiniTest.new_set()

T["next_hunk"]["does not error"] = function()
  local nav = get_navigation()
  -- Should not error even without diff mode
  nav.next_hunk()
end

T["prev_hunk"] = MiniTest.new_set()

T["prev_hunk"]["does not error"] = function()
  local nav = get_navigation()
  -- Should not error even without diff mode
  nav.prev_hunk()
end

-- =============================================================================
-- File Navigation Tests
-- =============================================================================

T["get_current_file_idx"] = MiniTest.new_set()

T["get_current_file_idx"]["returns 0 with no current file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = nil

  expect.equality(nav.get_current_file_idx(), 0)
end

T["get_current_file_idx"]["returns correct index"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.set_files({
    { path = "a.lua" },
    { path = "b.lua" },
    { path = "c.lua" },
  })
  state.state.current_file = "b.lua"

  expect.equality(nav.get_current_file_idx(), 2)
end

T["get_current_file_idx"]["returns 0 for nonexistent file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.set_files({
    { path = "a.lua" },
    { path = "b.lua" },
  })
  state.state.current_file = "nonexistent.lua"

  expect.equality(nav.get_current_file_idx(), 0)
end

T["open_next_file"] = MiniTest.new_set()

T["open_next_file"]["does nothing with no files"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.state.files = {}

  nav.open_next_file()
  -- Should not error
end

T["open_prev_file"] = MiniTest.new_set()

T["open_prev_file"]["does nothing with no files"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.state.files = {}

  nav.open_prev_file()
  -- Should not error
end

-- =============================================================================
-- File Tree Navigation Tests
-- =============================================================================

T["tree_next"] = MiniTest.new_set()

T["tree_next"]["does not error"] = function()
  local nav = get_navigation()
  -- Should not error even without file tree
  nav.tree_next()
end

T["tree_prev"] = MiniTest.new_set()

T["tree_prev"]["does not error"] = function()
  local nav = get_navigation()
  -- Should not error even without file tree
  nav.tree_prev()
end

-- =============================================================================
-- open_file Tests
-- =============================================================================

T["open_file"] = MiniTest.new_set()

T["open_file"]["returns false for nonexistent file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.active = true
  state.set_files({
    { path = "a.lua" },
  })

  local result = nav.open_file("nonexistent.lua")
  expect.equality(result, false)
end

-- =============================================================================
-- Focus Tests
-- =============================================================================

T["focus_tree"] = MiniTest.new_set()

T["focus_tree"]["does not error without layout"] = function()
  local nav = get_navigation()
  -- Should not error
  nav.focus_tree()
end

T["focus_diff"] = MiniTest.new_set()

T["focus_diff"]["does not error without layout"] = function()
  local nav = get_navigation()
  -- Should not error
  nav.focus_diff()
end

T["toggle_focus"] = MiniTest.new_set()

T["toggle_focus"]["does not error without layout"] = function()
  local nav = get_navigation()
  -- Should not error
  nav.toggle_focus()
end

-- =============================================================================
-- get_cursor_line Tests
-- =============================================================================

T["get_cursor_line"] = MiniTest.new_set()

T["get_cursor_line"]["returns line number"] = function()
  local nav = get_navigation()

  -- Create a test buffer and window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3" })
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 10,
    height = 3,
  })

  vim.api.nvim_win_set_cursor(win, { 2, 0 })
  local line = nav.get_cursor_line()
  expect.equality(line, 2)

  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- =============================================================================
-- goto_line Tests
-- =============================================================================

T["goto_line"] = MiniTest.new_set()

T["goto_line"]["does not error without layout"] = function()
  local nav = get_navigation()
  -- Should not error
  nav.goto_line(10)
end

-- =============================================================================
-- Comment in File Navigation Tests
-- =============================================================================

T["next_comment_in_file"] = MiniTest.new_set()

T["next_comment_in_file"]["returns nil with no current file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = nil

  local result = nav.next_comment_in_file()
  expect.equality(result, nil)
end

T["next_comment_in_file"]["returns nil with no comments in file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = "test.lua"
  state.set_comments({
    { id = "1", file = "other.lua", line = 10 },
  })

  local result = nav.next_comment_in_file()
  expect.equality(result, nil)
end

T["prev_comment_in_file"] = MiniTest.new_set()

T["prev_comment_in_file"]["returns nil with no current file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = nil

  local result = nav.prev_comment_in_file()
  expect.equality(result, nil)
end

T["prev_comment_in_file"]["returns nil with no comments in file"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_file = "test.lua"
  state.set_comments({
    { id = "1", file = "other.lua", line = 10 },
  })

  local result = nav.prev_comment_in_file()
  expect.equality(result, nil)
end

-- =============================================================================
-- get_comment_counts Tests
-- =============================================================================

T["get_comment_counts"] = MiniTest.new_set()

T["get_comment_counts"]["returns correct counts"] = function()
  local state = get_state()
  local nav = get_navigation()
  state.state.current_comment_idx = 2
  state.set_comments({
    { id = "1", file = "a.lua", line = 10 },
    { id = "2", file = "a.lua", line = 20 },
    { id = "3", file = "b.lua", line = 5, resolved = false },
    { id = "4", kind = "local", status = "pending", file = "c.lua", line = 1 },
    { id = "5", kind = "conversation" }, -- not sortable
  })

  local counts = nav.get_comment_counts()
  expect.equality(counts.total, 4) -- sorted comments (with file and line)
  expect.equality(counts.current, 2)
  expect.equality(counts.unresolved, 1)
  expect.equality(counts.pending, 1)
end

T["get_comment_counts"]["returns zeros for empty state"] = function()
  local state = get_state()
  local nav = get_navigation()

  local counts = nav.get_comment_counts()
  expect.equality(counts.total, 0)
  expect.equality(counts.current, 0)
  expect.equality(counts.unresolved, 0)
  expect.equality(counts.pending, 0)
end

return T
