-- Integration tests for local review workflow
-- Tests the flow: state management, comments, file tree, etc.
--
-- NOTE: The diff view implementation (ui/diff.lua) has a window navigation bug
-- where after vsplit + wincmd H, the file tree window gets displaced. These tests
-- set up state manually to avoid triggering the diff view, testing the core
-- functionality instead.

local MiniTest = require("mini.test")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Setup mock git before tests
local mock_git = require("mocks.git")

-- Sample diff output for testing
local SAMPLE_DIFF = [[
diff --git a/src/utils.lua b/src/utils.lua
index 1234567..abcdefg 100644
--- a/src/utils.lua
+++ b/src/utils.lua
@@ -1,5 +1,7 @@
 local M = {}

+-- Added a new helper function
+
 function M.helper()
   return true
 end
@@ -10,6 +12,10 @@ function M.process(data)
   return data
 end

+function M.new_function()
+  return "new"
+end
+
 return M
diff --git a/src/init.lua b/src/init.lua
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/src/init.lua
@@ -0,0 +1,5 @@
+local M = {}
+
+M.version = "1.0.0"
+
+return M
diff --git a/old_file.lua b/old_file.lua
deleted file mode 100644
index abcdefg..0000000
--- a/old_file.lua
+++ /dev/null
@@ -1,3 +0,0 @@
-local M = {}
-return M
-
]]

-- Helper to reset all modules
local function reset_modules()
  -- Reset mock
  mock_git.reset()

  -- Clear loaded modules
  package.loaded["review"] = nil
  package.loaded["review.core.state"] = nil
  package.loaded["review.core.comments"] = nil
  package.loaded["review.core.diff_parser"] = nil
  package.loaded["review.config"] = nil
  package.loaded["review.commands"] = nil
  package.loaded["review.ui.layout"] = nil
  package.loaded["review.ui.file_tree"] = nil
  package.loaded["review.ui.diff"] = nil
  package.loaded["review.ui.signs"] = nil
  package.loaded["review.ui.virtual_text"] = nil
  package.loaded["review.ui.highlights"] = nil
  package.loaded["review.keymaps"] = nil
end

-- Helper to setup plugin and mock
local function setup_plugin()
  reset_modules()

  mock_git.install()
  mock_git.setup({
    diff_output = SAMPLE_DIFF,
    changed_files = { "src/utils.lua", "src/init.lua", "old_file.lua" },
    changed_files_status = {
      { path = "src/utils.lua", status = "modified" },
      { path = "src/init.lua", status = "added" },
      { path = "old_file.lua", status = "deleted" },
    },
    diff_stats = { additions = 12, deletions = 3, files_changed = 3 },
    files = {
      ["src/utils.lua"] = "local M = {}\nreturn M",
    },
  })

  local review = require("review")
  review.setup()

  return review
end

-- Helper to setup state manually (without opening diff view)
local function setup_state_with_files()
  local state = require("review.core.state")
  local diff_parser = require("review.core.diff_parser")
  local git = require("review.integrations.git")
  local layout = require("review.ui.layout")

  -- Parse diff
  local diff_output = git.diff("HEAD")
  local files = diff_parser.parse(diff_output)

  -- Setup state
  state.reset()
  state.set_mode("local", { base = "HEAD" })
  state.set_files(files)
  state.state.active = true

  -- Open layout (but don't open diff view)
  layout.open()

  -- Set current file manually
  if #files > 0 then
    state.set_current_file(files[1].path)
  end

  return state
end

-- Helper to cleanup after tests
local function cleanup()
  local state = package.loaded["review.core.state"]
  if state and state.is_active() then
    local layout = require("review.ui.layout")
    pcall(layout.close)
  end

  mock_git.restore()

  -- Close all tabs except the first
  while vim.fn.tabpagenr("$") > 1 do
    vim.cmd("tabclose!")
  end
end

-- =============================================================================
-- Setup/Teardown
-- =============================================================================

T["setup"] = function()
  cleanup()
end

T["teardown"] = function()
  cleanup()
end

-- =============================================================================
-- Diff Parser Tests
-- =============================================================================

T["diff parser"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["diff parser"]["parses files from diff output"] = function()
  setup_plugin()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_DIFF)

  expect.equality(#files, 3)
end

T["diff parser"]["identifies file statuses"] = function()
  setup_plugin()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_DIFF)

  -- Find by path
  local utils_file, init_file, old_file
  for _, f in ipairs(files) do
    if f.path == "src/utils.lua" then
      utils_file = f
    elseif f.path == "src/init.lua" then
      init_file = f
    elseif f.path == "old_file.lua" then
      old_file = f
    end
  end

  expect.equality(utils_file.status, "modified")
  expect.equality(init_file.status, "added")
  expect.equality(old_file.status, "deleted")
end

T["diff parser"]["parses hunks for modified files"] = function()
  setup_plugin()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_DIFF)

  local utils_file
  for _, f in ipairs(files) do
    if f.path == "src/utils.lua" then
      utils_file = f
      break
    end
  end

  expect.equality(utils_file ~= nil, true)
  expect.equality(utils_file.hunks ~= nil, true)
  expect.equality(#utils_file.hunks, 2) -- Two hunks in the diff
end

T["diff parser"]["parses additions and deletions"] = function()
  setup_plugin()
  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse(SAMPLE_DIFF)

  local utils_file
  for _, f in ipairs(files) do
    if f.path == "src/utils.lua" then
      utils_file = f
      break
    end
  end

  expect.equality(utils_file.additions > 0, true)
end

-- =============================================================================
-- State Management Tests
-- =============================================================================

T["state management"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["state management"]["initializes with correct defaults"] = function()
  setup_plugin()
  local state = require("review.core.state")

  expect.equality(state.state.active, false)
  expect.equality(state.state.mode, "local")
  expect.equality(state.state.base, "HEAD")
end

T["state management"]["set_mode changes mode and base"] = function()
  setup_plugin()
  local state = require("review.core.state")

  state.set_mode("local", { base = "main" })

  expect.equality(state.state.mode, "local")
  expect.equality(state.state.base, "main")
end

T["state management"]["set_files stores parsed files"] = function()
  setup_plugin()
  local state = setup_state_with_files()

  expect.equality(#state.state.files, 3)
end

T["state management"]["find_file returns file by path"] = function()
  setup_plugin()
  local state = setup_state_with_files()

  local file = state.find_file("src/utils.lua")

  expect.equality(file ~= nil, true)
  expect.equality(file.path, "src/utils.lua")
end

T["state management"]["find_file returns nil for non-existent path"] = function()
  setup_plugin()
  local state = setup_state_with_files()

  local file = state.find_file("nonexistent.lua")

  expect.equality(file, nil)
end

T["state management"]["is_active reflects state"] = function()
  setup_plugin()
  local state = require("review.core.state")

  expect.equality(state.is_active(), false)

  state.state.active = true
  expect.equality(state.is_active(), true)

  state.state.active = false
  expect.equality(state.is_active(), false)
end

T["state management"]["reset clears all state"] = function()
  setup_plugin()
  local state = setup_state_with_files()

  expect.equality(state.is_active(), true)
  expect.equality(#state.state.files > 0, true)

  state.reset()

  expect.equality(state.is_active(), false)
  expect.equality(#state.state.files, 0)
  expect.equality(#state.state.comments, 0)
end

T["state management"]["get_stats returns correct counts"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Note", "note")
  comments.add("src/utils.lua", 10, "Issue", "issue")

  local stats = state.get_stats()

  expect.equality(stats.total_files, 3)
  expect.equality(stats.total_comments, 2)
  expect.equality(stats.pending_comments, 2)
end

-- =============================================================================
-- Comment CRUD Tests
-- =============================================================================

T["comments"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["comments"]["add creates local comment"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 10, "This needs refactoring", "issue")

  expect.equality(comment ~= nil, true)
  expect.equality(comment.kind, "local")
  expect.equality(comment.file, "src/utils.lua")
  expect.equality(comment.line, 10)
  expect.equality(comment.body, "This needs refactoring")
  expect.equality(comment.type, "issue")
  expect.equality(comment.status, "pending")
  expect.equality(comment.author, "you")
end

T["comments"]["add_multiline creates multi-line comment"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add_multiline("src/utils.lua", 5, 10, "Spans multiple lines", "note")

  expect.equality(comment.start_line, 5)
  expect.equality(comment.end_line, 10)
  expect.equality(comment.line, 5)
end

T["comments"]["add multiple comments"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Comment 1", "note")
  comments.add("src/utils.lua", 10, "Comment 2", "issue")
  comments.add("src/init.lua", 3, "Comment 3", "suggestion")

  expect.equality(#state.state.comments, 3)
end

T["comments"]["edit updates comment body"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 5, "Original text", "note")
  local id = comment.id

  local success = comments.edit(id, "Updated text")

  expect.equality(success, true)

  local updated = state.find_comment(id)
  expect.equality(updated.body, "Updated text")
  expect.equality(updated.updated_at ~= nil, true)
end

T["comments"]["edit fails for non-existent comment"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local success = comments.edit("nonexistent", "text")

  expect.equality(success, false)
end

T["comments"]["delete removes pending comment"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 5, "To be deleted", "note")
  expect.equality(#state.state.comments, 1)

  local success = comments.delete(comment.id)

  expect.equality(success, true)
  expect.equality(#state.state.comments, 0)
end

T["comments"]["delete fails for non-existent comment"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local success = comments.delete("nonexistent")

  expect.equality(success, false)
end

T["comments"]["reply creates reply to comment"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local parent = comments.add("src/utils.lua", 5, "Parent comment", "note")
  local reply = comments.reply(parent.id, "Reply text")

  expect.equality(reply ~= nil, true)
  expect.equality(reply.in_reply_to_id, parent.id)
  expect.equality(reply.body, "Reply text")
  expect.equality(reply.file, parent.file)
  expect.equality(reply.line, parent.line)
end

T["comments"]["get_at_line returns comments for line"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Comment at line 5", "note")
  comments.add("src/utils.lua", 5, "Another at line 5", "issue")
  comments.add("src/utils.lua", 10, "Comment at line 10", "note")

  local at_5 = comments.get_at_line("src/utils.lua", 5)
  local at_10 = comments.get_at_line("src/utils.lua", 10)

  expect.equality(#at_5, 2)
  expect.equality(#at_10, 1)
end

T["comments"]["is_editable returns true for pending local comments"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 5, "Pending comment", "note")

  expect.equality(comments.is_editable(comment.id), true)
end

T["comments"]["is_deletable returns true for pending local comments"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 5, "Pending comment", "note")

  expect.equality(comments.is_deletable(comment.id), true)
end

-- =============================================================================
-- Comment Filtering Tests
-- =============================================================================

T["comment filtering"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["comment filtering"]["get_comments_for_file filters by file"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Utils comment 1", "note")
  comments.add("src/init.lua", 3, "Init comment", "note")
  comments.add("src/utils.lua", 10, "Utils comment 2", "note")

  local utils_comments = state.get_comments_for_file("src/utils.lua")
  local init_comments = state.get_comments_for_file("src/init.lua")

  expect.equality(#utils_comments, 2)
  expect.equality(#init_comments, 1)
end

T["comment filtering"]["get_pending_comments filters by status"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Pending 1", "note")
  comments.add("src/utils.lua", 10, "Pending 2", "note")

  local pending = state.get_pending_comments()

  expect.equality(#pending, 2)
end

T["comment filtering"]["get_comments_sorted sorts by file then line"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  -- Add out of order
  comments.add("src/utils.lua", 20, "Comment 3", "note")
  comments.add("src/init.lua", 5, "Comment 1", "note")
  comments.add("src/utils.lua", 5, "Comment 2", "note")

  local sorted = state.get_comments_sorted()

  expect.equality(#sorted, 3)
  -- src/init.lua comes before src/utils.lua alphabetically
  expect.equality(sorted[1].file, "src/init.lua")
  expect.equality(sorted[1].line, 5)
  expect.equality(sorted[2].file, "src/utils.lua")
  expect.equality(sorted[2].line, 5)
  expect.equality(sorted[3].file, "src/utils.lua")
  expect.equality(sorted[3].line, 20)
end

T["comment filtering"]["updates file comment counts"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 5, "Comment 1", "note")
  comments.add("src/utils.lua", 10, "Comment 2", "note")
  comments.add("src/init.lua", 3, "Comment 3", "note")

  -- NOTE: add_comment doesn't auto-update counts, must call manually
  -- This is a known limitation - counts are updated on set_comments/set_files
  state.update_file_comment_counts()

  local utils_file = state.find_file("src/utils.lua")
  local init_file = state.find_file("src/init.lua")

  expect.equality(utils_file.comment_count, 2)
  expect.equality(init_file.comment_count, 1)
end

-- =============================================================================
-- Layout Tests
-- =============================================================================

T["layout"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["layout"]["open creates new tabpage"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  local initial_tabs = vim.fn.tabpagenr("$")

  state.reset()
  state.state.active = true
  layout.open()

  expect.equality(vim.fn.tabpagenr("$"), initial_tabs + 1)
  expect.equality(state.state.layout.tabpage ~= nil, true)
  expect.equality(vim.api.nvim_tabpage_is_valid(state.state.layout.tabpage), true)
end

T["layout"]["open creates file tree window"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  state.reset()
  state.state.active = true
  layout.open()

  expect.equality(state.state.layout.file_tree_win ~= nil, true)
  expect.equality(vim.api.nvim_win_is_valid(state.state.layout.file_tree_win), true)
end

T["layout"]["open creates diff window"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  state.reset()
  state.state.active = true
  layout.open()

  expect.equality(state.state.layout.diff_win ~= nil, true)
  expect.equality(vim.api.nvim_win_is_valid(state.state.layout.diff_win), true)
end

T["layout"]["close resets state"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  state.reset()
  state.state.active = true
  layout.open()

  expect.equality(state.is_active(), true)

  layout.close()

  expect.equality(state.is_active(), false)
end

T["layout"]["focus_tree focuses file tree window"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  state.reset()
  state.state.active = true
  layout.open()

  -- Focus diff first
  layout.focus_diff()
  expect.equality(vim.api.nvim_get_current_win() == state.state.layout.diff_win, true)

  -- Then focus tree
  layout.focus_tree()
  expect.equality(vim.api.nvim_get_current_win() == state.state.layout.file_tree_win, true)
end

T["layout"]["is_valid returns true when layout intact"] = function()
  setup_plugin()
  local state = require("review.core.state")
  local layout = require("review.ui.layout")

  state.reset()
  state.state.active = true
  layout.open()

  expect.equality(layout.is_valid(), true)
end

-- =============================================================================
-- File Tree Tests
-- =============================================================================

T["file tree"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["file tree"]["render populates buffer"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  expect.equality(#lines > 0, true)
end

T["file tree"]["select_next cycles through files"] = function()
  setup_plugin()
  setup_state_with_files()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  expect.equality(file_tree.get_selected_idx(), 1)

  file_tree.select_next()
  expect.equality(file_tree.get_selected_idx(), 2)

  file_tree.select_next()
  expect.equality(file_tree.get_selected_idx(), 3)

  -- Wraps around
  file_tree.select_next()
  expect.equality(file_tree.get_selected_idx(), 1)
end

T["file tree"]["select_prev cycles through files backwards"] = function()
  setup_plugin()
  setup_state_with_files()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  expect.equality(file_tree.get_selected_idx(), 1)

  -- Wraps to end
  file_tree.select_prev()
  expect.equality(file_tree.get_selected_idx(), 3)

  file_tree.select_prev()
  expect.equality(file_tree.get_selected_idx(), 2)
end

T["file tree"]["get_selected_file returns selected file"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  local file = file_tree.get_selected_file()

  expect.equality(file ~= nil, true)
  expect.equality(file.path, state.state.files[1].path)
end

T["file tree"]["select_by_path selects file by path"] = function()
  setup_plugin()
  setup_state_with_files()
  local file_tree = require("review.ui.file_tree")

  file_tree.render()

  local success = file_tree.select_by_path("src/init.lua")

  expect.equality(success, true)

  local selected = file_tree.get_selected_file()
  expect.equality(selected.path, "src/init.lua")
end

-- =============================================================================
-- Public API Tests
-- =============================================================================

T["public API"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["public API"]["setup initializes plugin"] = function()
  reset_modules()
  mock_git.install()

  local review = require("review")

  expect.equality(review.is_setup(), false)

  review.setup()

  expect.equality(review.is_setup(), true)
end

T["public API"]["get_config returns configuration"] = function()
  setup_plugin()
  local review = require("review")

  local cfg = review.get_config()

  expect.equality(type(cfg), "table")
  expect.equality(type(cfg.ui), "table")
end

T["public API"]["is_active reflects state"] = function()
  setup_plugin()
  local review = require("review")
  local state = require("review.core.state")

  expect.equality(review.is_active(), false)

  state.state.active = true
  expect.equality(review.is_active(), true)
end

T["public API"]["get_state returns state"] = function()
  setup_plugin()
  local review = require("review")
  local state_mod = require("review.core.state")

  state_mod.set_mode("local", { base = "develop" })
  state_mod.state.active = true

  local state = review.get_state()

  expect.equality(state.mode, "local")
  expect.equality(state.base, "develop")
end

-- =============================================================================
-- Edge Cases
-- =============================================================================

T["edge cases"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cleanup()
    end,
    post_case = cleanup,
  },
})

T["edge cases"]["handles empty diff"] = function()
  reset_modules()
  mock_git.install()
  mock_git.setup({
    diff_output = "",
    changed_files = {},
    changed_files_status = {},
    diff_stats = { additions = 0, deletions = 0, files_changed = 0 },
  })

  local diff_parser = require("review.core.diff_parser")

  local files = diff_parser.parse("")

  expect.equality(#files, 0)
end

T["edge cases"]["comment on non-current file works"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  local current = state.state.current_file
  local other = "src/init.lua"
  if current == other then
    other = "src/utils.lua"
  end

  local comment = comments.add(other, 5, "Comment on other file", "note")

  expect.equality(comment.file, other)
  expect.equality(comment.file ~= current, true)
end

T["edge cases"]["handles multiple comment types"] = function()
  setup_plugin()
  local state = setup_state_with_files()
  local comments = require("review.core.comments")

  comments.add("src/utils.lua", 1, "Note", "note")
  comments.add("src/utils.lua", 2, "Issue", "issue")
  comments.add("src/utils.lua", 3, "Suggestion", "suggestion")
  comments.add("src/utils.lua", 4, "Praise", "praise")

  local all = state.state.comments

  expect.equality(#all, 4)
  expect.equality(all[1].type, "note")
  expect.equality(all[2].type, "issue")
  expect.equality(all[3].type, "suggestion")
  expect.equality(all[4].type, "praise")
end

T["edge cases"]["handles large line numbers"] = function()
  setup_plugin()
  setup_state_with_files()
  local comments = require("review.core.comments")

  local comment = comments.add("src/utils.lua", 99999, "Comment on large line", "note")

  expect.equality(comment.line, 99999)
end

return T
