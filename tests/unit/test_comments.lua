-- Tests for review.nvim comments module
local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Helper to get fresh modules
local function get_modules()
  package.loaded["review.core.state"] = nil
  package.loaded["review.core.comments"] = nil
  package.loaded["review.utils"] = nil
  local state = require("review.core.state")
  local comments = require("review.core.comments")
  state.reset()
  return comments, state
end

-- =============================================================================
-- add Tests
-- =============================================================================

T["add"] = MiniTest.new_set()

T["add"]["creates local comment"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test comment")

  expect.equality(comment.kind, "local")
  expect.equality(comment.file, "test.lua")
  expect.equality(comment.line, 10)
  expect.equality(comment.body, "Test comment")
  expect.equality(comment.status, "pending")
  expect.equality(comment.author, "you")
end

T["add"]["defaults type to note"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  expect.equality(comment.type, "note")
end

T["add"]["accepts custom type"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Issue", "issue")

  expect.equality(comment.type, "issue")
end

T["add"]["generates unique id"] = function()
  local comments, _ = get_modules()
  local c1 = comments.add("test.lua", 10, "First")
  local c2 = comments.add("test.lua", 20, "Second")

  expect.no_equality(c1.id, c2.id)
end

T["add"]["adds to state"] = function()
  local comments, state = get_modules()
  comments.add("test.lua", 10, "Test")

  expect.equality(#state.state.comments, 1)
end

T["add"]["sets created_at timestamp"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  expect.no_equality(comment.created_at, nil)
  -- Check ISO format
  local match = comment.created_at:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$")
  expect.no_equality(match, nil)
end

-- =============================================================================
-- add_multiline Tests
-- =============================================================================

T["add_multiline"] = MiniTest.new_set()

T["add_multiline"]["creates multiline comment"] = function()
  local comments, _ = get_modules()
  local comment = comments.add_multiline("test.lua", 5, 10, "Multiline")

  expect.equality(comment.line, 5)
  expect.equality(comment.start_line, 5)
  expect.equality(comment.end_line, 10)
end

T["add_multiline"]["sets correct fields"] = function()
  local comments, _ = get_modules()
  local comment = comments.add_multiline("test.lua", 5, 10, "Test", "suggestion")

  expect.equality(comment.kind, "local")
  expect.equality(comment.type, "suggestion")
  expect.equality(comment.status, "pending")
end

-- =============================================================================
-- edit Tests
-- =============================================================================

T["edit"] = MiniTest.new_set()

T["edit"]["updates comment body"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Original")
  local success = comments.edit(comment.id, "Updated")

  expect.equality(success, true)
  local updated = state.find_comment(comment.id)
  expect.equality(updated.body, "Updated")
end

T["edit"]["sets updated_at timestamp"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Original")
  comments.edit(comment.id, "Updated")

  local updated = state.find_comment(comment.id)
  expect.no_equality(updated.updated_at, nil)
end

T["edit"]["returns false for missing id"] = function()
  local comments, _ = get_modules()
  local success = comments.edit("nonexistent", "Updated")

  expect.equality(success, false)
end

T["edit"]["only edits local comments"] = function()
  local comments, state = get_modules()
  -- Manually add a review comment (from GitHub)
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "GitHub comment",
  })

  local success = comments.edit("gh_1", "Try to edit")
  expect.equality(success, false)

  local comment = state.find_comment("gh_1")
  expect.equality(comment.body, "GitHub comment")
end

-- =============================================================================
-- delete Tests
-- =============================================================================

T["delete"] = MiniTest.new_set()

T["delete"]["removes comment from state"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test")
  local success = comments.delete(comment.id)

  expect.equality(success, true)
  expect.equality(#state.state.comments, 0)
end

T["delete"]["returns false for missing id"] = function()
  local comments, _ = get_modules()
  local success = comments.delete("nonexistent")

  expect.equality(success, false)
end

T["delete"]["only deletes pending comments"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test")
  comment.status = "submitted"

  local success = comments.delete(comment.id)
  expect.equality(success, false)
  expect.equality(#state.state.comments, 1)
end

T["delete"]["only deletes local comments"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "GitHub comment",
    status = "pending",
  })

  local success = comments.delete("gh_1")
  expect.equality(success, false)
end

-- =============================================================================
-- reply Tests
-- =============================================================================

T["reply"] = MiniTest.new_set()

T["reply"]["creates reply comment"] = function()
  local comments, _ = get_modules()
  local parent = comments.add("test.lua", 10, "Parent")
  local reply = comments.reply(parent.id, "Reply text")

  expect.no_equality(reply, nil)
  expect.equality(reply.body, "Reply text")
  expect.equality(reply.in_reply_to_id, parent.id)
end

T["reply"]["inherits file and line from parent"] = function()
  local comments, _ = get_modules()
  local parent = comments.add("test.lua", 10, "Parent")
  local reply = comments.reply(parent.id, "Reply")

  expect.equality(reply.file, "test.lua")
  expect.equality(reply.line, 10)
end

T["reply"]["adds to parent replies array"] = function()
  local comments, state = get_modules()
  local parent = comments.add("test.lua", 10, "Parent")
  comments.reply(parent.id, "Reply")

  local updated_parent = state.find_comment(parent.id)
  expect.equality(#updated_parent.replies, 1)
end

T["reply"]["adds to global state"] = function()
  local comments, state = get_modules()
  local parent = comments.add("test.lua", 10, "Parent")
  comments.reply(parent.id, "Reply")

  -- Parent + reply
  expect.equality(#state.state.comments, 2)
end

T["reply"]["returns nil for missing parent"] = function()
  local comments, _ = get_modules()
  local reply = comments.reply("nonexistent", "Reply")

  expect.equality(reply, nil)
end

-- =============================================================================
-- set_resolved Tests
-- =============================================================================

T["set_resolved"] = MiniTest.new_set()

T["set_resolved"]["sets resolved to true"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "Review comment",
    resolved = false,
  })

  local success = comments.set_resolved("gh_1", true)
  expect.equality(success, true)

  local comment = state.find_comment("gh_1")
  expect.equality(comment.resolved, true)
end

T["set_resolved"]["sets resolved to false"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "Review comment",
    resolved = true,
  })

  local success = comments.set_resolved("gh_1", false)
  expect.equality(success, true)

  local comment = state.find_comment("gh_1")
  expect.equality(comment.resolved, false)
end

T["set_resolved"]["returns false for missing id"] = function()
  local comments, _ = get_modules()
  local success = comments.set_resolved("nonexistent", true)

  expect.equality(success, false)
end

T["set_resolved"]["only works on review comments"] = function()
  local comments, state = get_modules()
  local local_comment = comments.add("test.lua", 10, "Local")

  local success = comments.set_resolved(local_comment.id, true)
  expect.equality(success, false)

  local comment = state.find_comment(local_comment.id)
  expect.equality(comment.resolved, nil)
end

-- =============================================================================
-- set_type Tests
-- =============================================================================

T["set_type"] = MiniTest.new_set()

T["set_type"]["changes type"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test", "note")

  local success = comments.set_type(comment.id, "issue")
  expect.equality(success, true)

  local updated = state.find_comment(comment.id)
  expect.equality(updated.type, "issue")
end

T["set_type"]["sets updated_at"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  comments.set_type(comment.id, "suggestion")
  local updated = state.find_comment(comment.id)
  expect.no_equality(updated.updated_at, nil)
end

T["set_type"]["returns false for non-local"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "Review",
  })

  local success = comments.set_type("gh_1", "issue")
  expect.equality(success, false)
end

-- =============================================================================
-- mark_submitted Tests
-- =============================================================================

T["mark_submitted"] = MiniTest.new_set()

T["mark_submitted"]["updates status and github_id"] = function()
  local comments, state = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  local success = comments.mark_submitted(comment.id, 12345)
  expect.equality(success, true)

  local updated = state.find_comment(comment.id)
  expect.equality(updated.status, "submitted")
  expect.equality(updated.github_id, 12345)
end

T["mark_submitted"]["returns false for missing id"] = function()
  local comments, _ = get_modules()
  local success = comments.mark_submitted("nonexistent", 123)

  expect.equality(success, false)
end

T["mark_submitted"]["only works on local comments"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "Review",
  })

  local success = comments.mark_submitted("gh_1", 123)
  expect.equality(success, false)
end

-- =============================================================================
-- get_at_line Tests
-- =============================================================================

T["get_at_line"] = MiniTest.new_set()

T["get_at_line"]["returns comments at line"] = function()
  local comments, _ = get_modules()
  comments.add("test.lua", 10, "First")
  comments.add("test.lua", 10, "Second")
  comments.add("test.lua", 20, "Other line")

  local at_line = comments.get_at_line("test.lua", 10)
  expect.equality(#at_line, 2)
end

T["get_at_line"]["returns empty for no matches"] = function()
  local comments, _ = get_modules()
  comments.add("test.lua", 10, "Test")

  local at_line = comments.get_at_line("test.lua", 20)
  expect.equality(#at_line, 0)
end

T["get_at_line"]["includes multiline comments"] = function()
  local comments, _ = get_modules()
  comments.add_multiline("test.lua", 5, 15, "Multiline")
  comments.add("test.lua", 10, "Single")

  local at_line = comments.get_at_line("test.lua", 10)
  expect.equality(#at_line, 2)
end

T["get_at_line"]["multiline excludes outside range"] = function()
  local comments, _ = get_modules()
  comments.add_multiline("test.lua", 5, 10, "Multiline")

  local at_line = comments.get_at_line("test.lua", 11)
  expect.equality(#at_line, 0)
end

-- =============================================================================
-- is_editable / is_deletable Tests
-- =============================================================================

T["is_editable"] = MiniTest.new_set()

T["is_editable"]["returns true for local pending"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  expect.equality(comments.is_editable(comment.id), true)
end

T["is_editable"]["returns false for submitted"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Test")
  comment.status = "submitted"

  expect.equality(comments.is_editable(comment.id), false)
end

T["is_editable"]["returns false for non-local"] = function()
  local comments, state = get_modules()
  state.add_comment({
    id = "gh_1",
    kind = "review",
    body = "Review",
    status = "pending",
  })

  expect.equality(comments.is_editable("gh_1"), false)
end

T["is_editable"]["returns false for missing"] = function()
  local comments, _ = get_modules()
  expect.equality(comments.is_editable("nonexistent"), false)
end

T["is_deletable"] = MiniTest.new_set()

T["is_deletable"]["matches is_editable behavior"] = function()
  local comments, _ = get_modules()
  local comment = comments.add("test.lua", 10, "Test")

  expect.equality(comments.is_deletable(comment.id), true)

  comment.status = "submitted"
  expect.equality(comments.is_deletable(comment.id), false)
end

-- =============================================================================
-- get_thread_root Tests
-- =============================================================================

T["get_thread_root"] = MiniTest.new_set()

T["get_thread_root"]["returns same for root comment"] = function()
  local comments, _ = get_modules()
  local root = comments.add("test.lua", 10, "Root")

  local found = comments.get_thread_root(root.id)
  expect.equality(found.id, root.id)
end

T["get_thread_root"]["finds root from reply"] = function()
  local comments, _ = get_modules()
  local root = comments.add("test.lua", 10, "Root")
  local reply = comments.reply(root.id, "Reply")

  local found = comments.get_thread_root(reply.id)
  expect.equality(found.id, root.id)
end

T["get_thread_root"]["returns nil for missing"] = function()
  local comments, _ = get_modules()
  local found = comments.get_thread_root("nonexistent")

  expect.equality(found, nil)
end

-- =============================================================================
-- count_replies Tests
-- =============================================================================

T["count_replies"] = MiniTest.new_set()

T["count_replies"]["returns zero for no replies"] = function()
  local comments, _ = get_modules()
  local root = comments.add("test.lua", 10, "Root")

  expect.equality(comments.count_replies(root.id), 0)
end

T["count_replies"]["counts replies correctly"] = function()
  local comments, _ = get_modules()
  local root = comments.add("test.lua", 10, "Root")
  comments.reply(root.id, "Reply 1")
  comments.reply(root.id, "Reply 2")
  comments.reply(root.id, "Reply 3")

  expect.equality(comments.count_replies(root.id), 3)
end

T["count_replies"]["returns zero for missing id"] = function()
  local comments, _ = get_modules()
  expect.equality(comments.count_replies("nonexistent"), 0)
end

return T
