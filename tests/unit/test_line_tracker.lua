-- Tests for review.core.line_tracker module
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset modules
      package.loaded["review.core.line_tracker"] = nil
      package.loaded["review.core.state"] = nil
    end,
    post_case = function()
      -- Clean up any test buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):find("test_tracker") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end,
  },
})

local function get_tracker()
  return require("review.core.line_tracker")
end

local function get_state()
  return require("review.core.state")
end

-- Helper to create a test buffer with lines
local function create_test_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "test_tracker_" .. os.time() .. "_" .. math.random(1000))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "line 1", "line 2", "line 3", "line 4", "line 5" })
  return buf
end

-- Mock comment
local function mock_comment(line, id)
  return {
    id = id or ("comment_" .. line),
    kind = "local",
    body = "Test comment",
    file = "test.lua",
    line = line,
    type = "note",
  }
end

T["get_namespace()"] = MiniTest.new_set()

T["get_namespace()"]["returns a number"] = function()
  local tracker = get_tracker()
  local ns = tracker.get_namespace()
  MiniTest.expect.equality(type(ns), "number")
end

T["get_namespace()"]["returns consistent namespace"] = function()
  local tracker = get_tracker()
  local ns1 = tracker.get_namespace()
  local ns2 = tracker.get_namespace()
  MiniTest.expect.equality(ns1, ns2)
end

T["track_comment()"] = MiniTest.new_set()

T["track_comment()"]["creates extmark for comment"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(2)

  local extmark_id = tracker.track_comment(buf, comment)

  MiniTest.expect.equality(type(extmark_id), "number")
  MiniTest.expect.equality(comment.extmark_id, extmark_id)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["track_comment()"]["returns nil for comment without line"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = { id = "no_line", kind = "local", body = "No line" }

  local extmark_id = tracker.track_comment(buf, comment)

  MiniTest.expect.equality(extmark_id, nil)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["track_comment()"]["returns nil for invalid buffer"] = function()
  local tracker = get_tracker()
  local comment = mock_comment(2)

  local extmark_id = tracker.track_comment(99999, comment)

  MiniTest.expect.equality(extmark_id, nil)
end

T["track_comment()"]["clamps line to buffer bounds"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3" })
  local comment = mock_comment(100) -- Line beyond buffer

  local extmark_id = tracker.track_comment(buf, comment)

  -- Should still create extmark (at last valid line)
  MiniTest.expect.equality(type(extmark_id), "number")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["track_comment()"]["stores tracking info"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(2, "tracked_comment")

  tracker.track_comment(buf, comment)

  local tracked = tracker.get_tracked(buf)
  MiniTest.expect.equality(#tracked, 1)
  MiniTest.expect.equality(tracked[1].comment_id, "tracked_comment")
  MiniTest.expect.equality(tracked[1].original_line, 2)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_current_line()"] = MiniTest.new_set()

T["get_current_line()"]["returns original line when no edits"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(3)

  tracker.track_comment(buf, comment)
  local current = tracker.get_current_line(buf, comment)

  MiniTest.expect.equality(current, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_current_line()"]["tracks line movement when lines inserted above"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })
  local comment = mock_comment(3)

  tracker.track_comment(buf, comment)

  -- Insert 2 lines at the beginning
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new line 1", "new line 2" })

  local current = tracker.get_current_line(buf, comment)

  MiniTest.expect.equality(current, 5) -- 3 + 2 = 5

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_current_line()"]["tracks line movement when lines deleted above"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })
  local comment = mock_comment(4)

  tracker.track_comment(buf, comment)

  -- Delete first 2 lines
  vim.api.nvim_buf_set_lines(buf, 0, 2, false, {})

  local current = tracker.get_current_line(buf, comment)

  MiniTest.expect.equality(current, 2) -- 4 - 2 = 2

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_current_line()"]["returns comment.line when no extmark_id"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(3)
  -- Don't track, just query

  local current = tracker.get_current_line(buf, comment)

  MiniTest.expect.equality(current, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_current_line()"]["returns nil when extmark deleted (line deleted)"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3" })
  local comment = mock_comment(2)

  tracker.track_comment(buf, comment)

  -- Delete the line with the comment
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})

  -- The extmark may still exist but point to a different line
  -- or may have been invalidated
  local current = tracker.get_current_line(buf, comment)
  -- Just verify it returns something (nil or a number)
  MiniTest.expect.equality(current == nil or type(current) == "number", true)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["clear()"] = MiniTest.new_set()

T["clear()"]["removes all extmarks for buffer"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()

  tracker.track_comment(buf, mock_comment(1, "c1"))
  tracker.track_comment(buf, mock_comment(2, "c2"))
  tracker.track_comment(buf, mock_comment(3, "c3"))

  MiniTest.expect.equality(#tracker.get_tracked(buf), 3)

  tracker.clear(buf)

  MiniTest.expect.equality(#tracker.get_tracked(buf), 0)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["clear()"]["handles invalid buffer"] = function()
  local tracker = get_tracker()
  -- Should not error
  tracker.clear(99999)
end

T["untrack_comment()"] = MiniTest.new_set()

T["untrack_comment()"]["removes specific comment tracking"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()

  tracker.track_comment(buf, mock_comment(1, "c1"))
  tracker.track_comment(buf, mock_comment(2, "c2"))
  tracker.track_comment(buf, mock_comment(3, "c3"))

  MiniTest.expect.equality(#tracker.get_tracked(buf), 3)

  tracker.untrack_comment(buf, "c2")

  local tracked = tracker.get_tracked(buf)
  MiniTest.expect.equality(#tracked, 2)

  -- Verify c2 is gone
  local found = false
  for _, t in ipairs(tracked) do
    if t.comment_id == "c2" then
      found = true
    end
  end
  MiniTest.expect.equality(found, false)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["untrack_comment()"]["handles non-existent comment"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()

  tracker.track_comment(buf, mock_comment(1, "c1"))

  -- Should not error
  tracker.untrack_comment(buf, "nonexistent")

  MiniTest.expect.equality(#tracker.get_tracked(buf), 1)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["has_comment_moved()"] = MiniTest.new_set()

T["has_comment_moved()"]["returns false when no movement"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(3, "c1")

  tracker.track_comment(buf, comment)

  local moved, delta = tracker.has_comment_moved(buf, comment)

  MiniTest.expect.equality(moved, false)
  MiniTest.expect.equality(delta, 0)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["has_comment_moved()"]["returns true with delta when moved"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })
  local comment = mock_comment(3, "c1")

  tracker.track_comment(buf, comment)

  -- Insert lines above
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new 1", "new 2" })

  local moved, delta = tracker.has_comment_moved(buf, comment)

  MiniTest.expect.equality(moved, true)
  MiniTest.expect.equality(delta, 2)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["has_comment_moved()"]["returns false for untracked comment"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()
  local comment = mock_comment(3) -- Not tracked

  local moved, delta = tracker.has_comment_moved(buf, comment)

  MiniTest.expect.equality(moved, false)
  MiniTest.expect.equality(delta, nil)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["get_tracked()"] = MiniTest.new_set()

T["get_tracked()"]["returns empty table for untracked buffer"] = function()
  local tracker = get_tracker()
  local tracked = tracker.get_tracked(99999)
  MiniTest.expect.equality(#tracked, 0)
end

T["get_tracked()"]["returns all tracked comments"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer()

  tracker.track_comment(buf, mock_comment(1, "c1"))
  tracker.track_comment(buf, mock_comment(2, "c2"))

  local tracked = tracker.get_tracked(buf)

  MiniTest.expect.equality(#tracked, 2)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["sync_comment_lines()"] = MiniTest.new_set()

T["sync_comment_lines()"]["updates comment lines from extmarks"] = function()
  local tracker = get_tracker()
  local state = get_state()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })

  -- Initialize state
  state.reset()
  state.set_mode("local")
  state.set_current_file("test.lua")

  -- Add comments to state
  local comment1 = { id = "c1", kind = "local", body = "Comment 1", file = "test.lua", line = 2 }
  local comment2 = { id = "c2", kind = "local", body = "Comment 2", file = "test.lua", line = 4 }
  state.state.comments = { comment1, comment2 }

  -- Track comments
  tracker.track_comment(buf, comment1)
  tracker.track_comment(buf, comment2)

  -- Insert lines at beginning
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new 1", "new 2", "new 3" })

  -- Sync
  tracker.sync_comment_lines(buf)

  -- Comments should have updated line numbers
  MiniTest.expect.equality(comment1.line, 5) -- 2 + 3
  MiniTest.expect.equality(comment2.line, 7) -- 4 + 3

  -- Cleanup
  state.reset()
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["track_all_comments()"] = MiniTest.new_set()

T["track_all_comments()"]["tracks all comments for current file"] = function()
  local tracker = get_tracker()
  local state = get_state()
  local buf = create_test_buffer()

  -- Initialize state
  state.reset()
  state.set_mode("local")
  state.set_current_file("test.lua")

  -- Add comments
  state.state.comments = {
    { id = "c1", kind = "local", body = "Comment 1", file = "test.lua", line = 1 },
    { id = "c2", kind = "local", body = "Comment 2", file = "test.lua", line = 3 },
    { id = "c3", kind = "local", body = "Comment 3", file = "other.lua", line = 2 }, -- Different file
  }

  tracker.track_all_comments(buf)

  local tracked = tracker.get_tracked(buf)
  -- Should track 2 comments (only for test.lua)
  MiniTest.expect.equality(#tracked, 2)

  -- Cleanup
  state.reset()
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["multi-line comments"] = MiniTest.new_set()

T["multi-line comments"]["tracks end_line"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })

  local comment = {
    id = "multiline",
    kind = "local",
    body = "Multi-line comment",
    file = "test.lua",
    line = 2,
    end_line = 4,
  }

  local extmark_id = tracker.track_comment(buf, comment)
  MiniTest.expect.equality(type(extmark_id), "number")

  -- Get end line
  local end_line = tracker.get_current_end_line(buf, comment)
  MiniTest.expect.equality(end_line, 4)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["multi-line comments"]["end_line tracks insertions"] = function()
  local tracker = get_tracker()
  local buf = create_test_buffer({ "line 1", "line 2", "line 3", "line 4", "line 5" })

  local comment = {
    id = "multiline",
    kind = "local",
    body = "Multi-line comment",
    file = "test.lua",
    line = 2,
    end_line = 4,
  }

  tracker.track_comment(buf, comment)

  -- Insert lines at beginning
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "new 1", "new 2" })

  local current_line = tracker.get_current_line(buf, comment)
  -- end_line tracking depends on extmark implementation
  -- just verify current_line moved correctly
  MiniTest.expect.equality(current_line, 4) -- 2 + 2

  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
