-- Tests for review.ui.file_tree module (directory-grouped implementation)
local T = MiniTest.new_set()

local file_tree = require("review.ui.file_tree")
local state = require("review.core.state")
local config = require("review.config")
local layout = require("review.ui.layout")

-- Sample file data for testing
local function create_test_files()
  return {
    {
      path = "src/main.lua",
      status = "modified",
      additions = 10,
      deletions = 5,
      comment_count = 2,
      hunks = {},
      reviewed = false,
    },
    {
      path = "src/utils.lua",
      status = "added",
      additions = 50,
      deletions = 0,
      comment_count = 0,
      hunks = {},
      reviewed = true,
    },
    {
      path = "tests/test_main.lua",
      status = "modified",
      additions = 5,
      deletions = 2,
      comment_count = 1,
      hunks = {},
      reviewed = false,
    },
    {
      path = "README.md",
      status = "deleted",
      additions = 0,
      deletions = 10,
      comment_count = 0,
      hunks = {},
      reviewed = false,
    },
  }
end

-- Helper to clean up after tests
local function cleanup()
  pcall(function()
    layout.cleanup_autocmds()
  end)
  pcall(function()
    local buf = state.state.layout.file_tree_buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)
  pcall(function()
    if state.state.layout.tabpage and vim.api.nvim_tabpage_is_valid(state.state.layout.tabpage) then
      local tabs = vim.api.nvim_list_tabpages()
      if #tabs > 1 then
        local tab_nr = vim.api.nvim_tabpage_get_number(state.state.layout.tabpage)
        vim.cmd("tabclose! " .. tab_nr)
      end
    end
  end)
  state.reset()
  file_tree.reset()
end

-- ============================================================================
-- get_status_letter tests
-- ============================================================================

T["get_status_letter()"] = MiniTest.new_set()

T["get_status_letter()"]["returns A for added files"] = function()
  config.setup()
  local letter, hl = file_tree.get_status_letter("added")
  MiniTest.expect.equality(letter, "A")
  MiniTest.expect.equality(hl, "ReviewTreeAdded")
end

T["get_status_letter()"]["returns M for modified files"] = function()
  config.setup()
  local letter, hl = file_tree.get_status_letter("modified")
  MiniTest.expect.equality(letter, "M")
  MiniTest.expect.equality(hl, "ReviewTreeModified")
end

T["get_status_letter()"]["returns D for deleted files"] = function()
  config.setup()
  local letter, hl = file_tree.get_status_letter("deleted")
  MiniTest.expect.equality(letter, "D")
  MiniTest.expect.equality(hl, "ReviewTreeDeleted")
end

T["get_status_letter()"]["returns R for renamed files"] = function()
  config.setup()
  local letter, hl = file_tree.get_status_letter("renamed")
  MiniTest.expect.equality(letter, "R")
  MiniTest.expect.equality(hl, "ReviewTreeRenamed")
end

T["get_status_letter()"]["returns ? for unknown status"] = function()
  config.setup()
  local letter, hl = file_tree.get_status_letter("unknown")
  MiniTest.expect.equality(letter, "?")
  MiniTest.expect.equality(hl, "ReviewTreeFile")
end

-- ============================================================================
-- get_reviewed_icon tests
-- ============================================================================

T["get_reviewed_icon()"] = MiniTest.new_set()

T["get_reviewed_icon()"]["returns checkmark for reviewed files"] = function()
  local icon, hl = file_tree.get_reviewed_icon(true)
  MiniTest.expect.equality(icon, "✓")
  MiniTest.expect.equality(hl, "ReviewTreeReviewed")
end

T["get_reviewed_icon()"]["returns dot for unreviewed files"] = function()
  local icon, hl = file_tree.get_reviewed_icon(false)
  MiniTest.expect.equality(icon, "·")
  MiniTest.expect.equality(hl, "ReviewTreePending")
end

-- ============================================================================
-- render_header tests
-- ============================================================================

T["render_header()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["render_header()"]["shows Local mode header"] = function()
  state.state.mode = "local"
  state.state.base = "HEAD"
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[1], "Local • HEAD (4 files)")
end

T["render_header()"]["shows PR mode header with PR number"] = function()
  state.state.mode = "pr"
  state.state.pr = { number = 123, title = "Test PR", base = "main", branch = "feat/test" }
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[1], "PR #123 (4 files)")
end

T["render_header()"]["shows branch info for PR mode"] = function()
  state.state.mode = "pr"
  state.state.pr = { number = 123, title = "Test PR", base = "main", branch = "feat/test" }
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[2], "main ← feat/test")
end

T["render_header()"]["shows review progress"] = function()
  state.state.mode = "local"
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  -- 1 file is reviewed, 4 total
  MiniTest.expect.equality(lines[2], "1/4 reviewed")
end

T["render_header()"]["includes blank line separator"] = function()
  state.state.mode = "local"
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  -- Last line should be blank
  MiniTest.expect.equality(lines[#lines], "")
end

T["render_header()"]["adds header highlight"] = function()
  state.state.mode = "local"
  state.state.files = {}
  local _, highlights = file_tree.render_header()
  MiniTest.expect.equality(highlights[1].hl_group, "ReviewTreeHeader")
  MiniTest.expect.equality(highlights[1].line, 1)
end

-- ============================================================================
-- render_footer tests
-- ============================================================================

T["render_footer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["render_footer()"]["shows pending count"] = function()
  state.state.comments = {
    { id = "1", kind = "review", body = "test" },
    { id = "2", kind = "review", body = "test2" },
    { id = "3", kind = "local", body = "pending", status = "pending" },
  }
  local lines, _ = file_tree.render_footer()
  -- First line is blank separator
  MiniTest.expect.equality(lines[1], "")
  -- Find line with pending count
  local found_pending = false
  for _, line in ipairs(lines) do
    if line:match("1 pending") then
      found_pending = true
    end
  end
  MiniTest.expect.equality(found_pending, true)
end

T["render_footer()"]["shows thread count in PR mode"] = function()
  state.state.mode = "pr"
  state.state.comments = {
    { id = "1", kind = "review", body = "test" },
    { id = "2", kind = "review", body = "test2" },
    { id = "3", kind = "conversation", body = "test3" },
  }
  local lines, _ = file_tree.render_footer()
  local found_threads = false
  for _, line in ipairs(lines) do
    if line:match("3 threads") then
      found_threads = true
    end
  end
  MiniTest.expect.equality(found_threads, true)
end

T["render_footer()"]["is empty when no comments"] = function()
  state.state.mode = "local"
  state.state.comments = {}
  local lines, _ = file_tree.render_footer()
  -- Only blank line, no footer content
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1], "")
end

-- ============================================================================
-- render_file_line tests
-- ============================================================================

T["render_file_line()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["render_file_line()"]["includes reviewed icon"] = function()
  local file = { path = "test.lua", status = "modified", reviewed = true }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  MiniTest.expect.equality(line:match("✓") ~= nil, true)
end

T["render_file_line()"]["includes unreviewed icon"] = function()
  local file = { path = "test.lua", status = "modified", reviewed = false }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  MiniTest.expect.equality(line:match("·") ~= nil, true)
end

T["render_file_line()"]["includes status letter"] = function()
  local file = { path = "test.lua", status = "added", reviewed = false }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  MiniTest.expect.equality(line:match("A") ~= nil, true)
end

T["render_file_line()"]["includes filename only (directory is in header)"] = function()
  local file = { path = "src/test.lua", status = "modified", reviewed = false }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  -- Now shows only filename, directory is shown in header
  MiniTest.expect.equality(line:match("test.lua") ~= nil, true)
end

T["render_file_line()"]["includes comment count"] = function()
  state.state.comments = {
    { id = "1", file = "test.lua", kind = "review", body = "test" },
    { id = "2", file = "test.lua", kind = "review", body = "test2" },
  }
  local file = { path = "test.lua", status = "modified", reviewed = false }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  MiniTest.expect.equality(line:match("2") ~= nil, true)
end

T["render_file_line()"]["shows asterisk for pending comments"] = function()
  state.state.comments = {
    { id = "1", file = "test.lua", kind = "local", body = "pending", status = "pending" },
  }
  local file = { path = "test.lua", status = "modified", reviewed = false }
  local line, _ = file_tree.render_file_line(file, 1, 50)
  MiniTest.expect.equality(line:match("1%*") ~= nil, true)
end

-- ============================================================================
-- Selection tests
-- ============================================================================

T["selection"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      state.state.files = create_test_files()
      file_tree.reset()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["selection"]["get_selected_idx returns 1 initially"] = function()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 1)
end

T["selection"]["select_next increments index"] = function()
  file_tree.select_next()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 2)
end

T["selection"]["select_next wraps around at end"] = function()
  file_tree.set_selected_idx(4) -- Last file
  file_tree.select_next()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 1)
end

T["selection"]["select_prev decrements index"] = function()
  file_tree.set_selected_idx(3)
  file_tree.select_prev()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 2)
end

T["selection"]["select_prev wraps around at start"] = function()
  file_tree.set_selected_idx(1)
  file_tree.select_prev()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 4) -- Last file
end

T["selection"]["set_selected_idx clamps to valid range"] = function()
  file_tree.set_selected_idx(100)
  MiniTest.expect.equality(file_tree.get_selected_idx(), 4) -- Max is 4
  file_tree.set_selected_idx(-5)
  MiniTest.expect.equality(file_tree.get_selected_idx(), 1) -- Min is 1
end

T["selection"]["get_selected_file returns correct file"] = function()
  file_tree.set_selected_idx(2)
  local file = file_tree.get_selected_file()
  MiniTest.expect.no_equality(file, nil)
  -- With directory grouping: (root)/README.md=1, src/main.lua=2
  MiniTest.expect.equality(file.path, "src/main.lua")
end

T["selection"]["get_selected_file returns nil for empty files"] = function()
  state.state.files = {}
  local file = file_tree.get_selected_file()
  MiniTest.expect.equality(file, nil)
end

-- ============================================================================
-- select_by_path tests
-- ============================================================================

T["select_by_path()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
      state.state.files = create_test_files()
      file_tree.reset()
    end,
    post_case = function()
      state.reset()
      file_tree.reset()
    end,
  },
})

T["select_by_path()"]["selects file by path"] = function()
  local success = file_tree.select_by_path("tests/test_main.lua")
  MiniTest.expect.equality(success, true)
  -- With directory grouping: (root)/README.md=1, src/main.lua=2, src/utils.lua=3, tests/test_main.lua=4
  MiniTest.expect.equality(file_tree.get_selected_idx(), 4)
end

T["select_by_path()"]["returns false for non-existent path"] = function()
  local success = file_tree.select_by_path("nonexistent.lua")
  MiniTest.expect.equality(success, false)
end

T["select_by_path()"]["does not change selection on failure"] = function()
  file_tree.set_selected_idx(2)
  file_tree.select_by_path("nonexistent.lua")
  MiniTest.expect.equality(file_tree.get_selected_idx(), 2)
end

-- ============================================================================
-- reset tests
-- ============================================================================

T["reset()"] = MiniTest.new_set()

T["reset()"]["resets selected_idx to 1"] = function()
  config.setup()
  state.state.files = create_test_files()
  file_tree.set_selected_idx(3)
  file_tree.reset()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 1)
end

-- ============================================================================
-- render tests (with layout)
-- ============================================================================

T["render()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
      state.state.files = create_test_files()
      state.state.comments = {}
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["render()"]["populates buffer with content"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true)
end

T["render()"]["includes header line with Local"] = function()
  state.state.mode = "local"
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1]:match("Local") ~= nil, true)
end

T["render()"]["includes file names"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  MiniTest.expect.equality(content:match("main.lua") ~= nil, true)
  MiniTest.expect.equality(content:match("utils.lua") ~= nil, true)
end

T["render()"]["includes directory headers"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  -- Directory headers now show directories with trailing slash
  MiniTest.expect.equality(content:match("src/") ~= nil, true)
  MiniTest.expect.equality(content:match("tests/") ~= nil, true)
end

T["render()"]["includes status letters"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  -- Should have M for modified, A for added, D for deleted
  MiniTest.expect.equality(content:match(" M ") ~= nil, true)
  MiniTest.expect.equality(content:match(" A ") ~= nil, true)
  MiniTest.expect.equality(content:match(" D ") ~= nil, true)
end

T["render()"]["includes reviewed icons"] = function()
  -- Use PR mode to avoid sync_reviewed_with_staged resetting reviewed status
  state.state.mode = "pr"
  state.state.pr = { number = 1, base = "main", branch = "test" }
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  -- Should have ✓ for reviewed and · for unreviewed
  MiniTest.expect.equality(content:match("✓") ~= nil, true)
  MiniTest.expect.equality(content:match("·") ~= nil, true)
end

T["render()"]["sets buffer to non-modifiable"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
end

T["render()"]["handles empty files list"] = function()
  state.state.files = {}
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true) -- Should still have header/footer
end

T["render()"]["does not error with invalid buffer"] = function()
  state.state.layout.file_tree_buf = 99999
  -- Should not error
  file_tree.render()
end

-- ============================================================================
-- init tests
-- ============================================================================

T["init()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
      state.state.files = create_test_files()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["init()"]["resets selection state"] = function()
  file_tree.set_selected_idx(3)
  file_tree.init()
  MiniTest.expect.equality(file_tree.get_selected_idx(), 1)
end

T["init()"]["renders the tree"] = function()
  file_tree.init()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines > 0, true)
end

T["init()"]["sets up keymaps"] = function()
  file_tree.init()
  local buf = state.state.layout.file_tree_buf
  local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
  local has_j = false
  local has_cr = false
  local has_space = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "j" then
      has_j = true
    end
    if km.lhs == "<CR>" then
      has_cr = true
    end
    if km.lhs == "<Space>" or km.lhs == " " then
      has_space = true
    end
  end
  MiniTest.expect.equality(has_j, true)
  MiniTest.expect.equality(has_cr, true)
  MiniTest.expect.equality(has_space, true)
end

-- ============================================================================
-- open_selected tests
-- ============================================================================

T["open_selected()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
      state.state.files = create_test_files()
      file_tree.reset()
      -- Mock the diff module's open_file to succeed
      local diff = require("review.ui.diff")
      diff._original_open_file = diff.open_file
      diff.open_file = function(path)
        state.set_current_file(path)
        return true
      end
    end,
    post_case = function()
      -- Restore original open_file
      local diff = require("review.ui.diff")
      if diff._original_open_file then
        diff.open_file = diff._original_open_file
        diff._original_open_file = nil
      end
      state.reset()
      file_tree.reset()
    end,
  },
})

T["open_selected()"]["sets current_file in state"] = function()
  -- With directory grouping: (root)/README.md=1, src/main.lua=2
  file_tree.set_selected_idx(2)
  file_tree.open_selected()
  MiniTest.expect.equality(state.state.current_file, "src/main.lua")
end

T["open_selected()"]["returns true on success"] = function()
  local result = file_tree.open_selected()
  MiniTest.expect.equality(result, true)
end

T["open_selected()"]["returns false when no files"] = function()
  state.state.files = {}
  local result = file_tree.open_selected()
  MiniTest.expect.equality(result, false)
end

T["open_selected()"]["calls on_file_select callback if configured"] = function()
  local called_with = nil
  config.setup({
    callbacks = {
      on_file_select = function(file)
        called_with = file
      end,
    },
  })
  -- With directory grouping: (root)/README.md=1, src/main.lua=2
  file_tree.set_selected_idx(2)
  file_tree.open_selected()
  MiniTest.expect.no_equality(called_with, nil)
  MiniTest.expect.equality(called_with.path, "src/main.lua")
end

-- ============================================================================
-- toggle_reviewed tests
-- ============================================================================

T["toggle_reviewed()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
      state.state.mode = "pr" -- Use PR mode to avoid git operations
      state.state.files = create_test_files()
      file_tree.reset()
    end,
    post_case = function()
      state.reset()
      file_tree.reset()
    end,
  },
})

T["toggle_reviewed()"]["toggles reviewed status in state"] = function()
  file_tree.set_selected_idx(1) -- src/main.lua, reviewed = false
  local file_before = file_tree.get_selected_file()
  MiniTest.expect.equality(file_before.reviewed, false)

  file_tree.toggle_reviewed()

  local file_after = file_tree.get_selected_file()
  MiniTest.expect.equality(file_after.reviewed, true)
end

T["toggle_reviewed()"]["returns new status"] = function()
  file_tree.set_selected_idx(1) -- reviewed = false
  local new_status = file_tree.toggle_reviewed()
  MiniTest.expect.equality(new_status, true)
end

T["toggle_reviewed()"]["returns nil when no file selected"] = function()
  state.state.files = {}
  local result = file_tree.toggle_reviewed()
  MiniTest.expect.equality(result, nil)
end

-- ============================================================================
-- Directory grouping tests
-- ============================================================================

T["split_path()"] = MiniTest.new_set()

T["split_path()"]["splits path into directory and filename"] = function()
  local dir, filename = file_tree.split_path("src/components/Button.tsx")
  MiniTest.expect.equality(dir, "src/components")
  MiniTest.expect.equality(filename, "Button.tsx")
end

T["split_path()"]["handles root-level files"] = function()
  local dir, filename = file_tree.split_path("README.md")
  MiniTest.expect.equality(dir, "")
  MiniTest.expect.equality(filename, "README.md")
end

T["split_path()"]["handles single-level paths"] = function()
  local dir, filename = file_tree.split_path("src/file.lua")
  MiniTest.expect.equality(dir, "src")
  MiniTest.expect.equality(filename, "file.lua")
end

T["group_files_by_directory()"] = MiniTest.new_set()

T["group_files_by_directory()"]["groups files correctly"] = function()
  local files = {
    { path = "src/a.lua" },
    { path = "src/b.lua" },
    { path = "tests/test.lua" },
    { path = "README.md" },
  }
  local groups, dirs = file_tree.group_files_by_directory(files)

  MiniTest.expect.equality(#dirs, 3) -- "", "src", "tests"
  MiniTest.expect.equality(#groups[""], 1) -- README.md
  MiniTest.expect.equality(#groups["src"], 2) -- a.lua, b.lua
  MiniTest.expect.equality(#groups["tests"], 1) -- test.lua
end

T["group_files_by_directory()"]["sorts directories alphabetically"] = function()
  local files = {
    { path = "zebra/z.lua" },
    { path = "alpha/a.lua" },
    { path = "README.md" },
  }
  local _, dirs = file_tree.group_files_by_directory(files)

  MiniTest.expect.equality(dirs[1], "") -- root first
  MiniTest.expect.equality(dirs[2], "alpha")
  MiniTest.expect.equality(dirs[3], "zebra")
end

T["directory expansion"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      state.reset()
      state.state.files = create_test_files()
      file_tree.reset()
    end,
    post_case = function()
      state.reset()
      file_tree.reset()
    end,
  },
})

T["directory expansion"]["directories default to expanded"] = function()
  MiniTest.expect.equality(file_tree.is_expanded("src"), true)
  MiniTest.expect.equality(file_tree.is_expanded("tests"), true)
  MiniTest.expect.equality(file_tree.is_expanded("nonexistent"), true)
end

T["directory expansion"]["toggle_directory collapses expanded dir"] = function()
  file_tree.toggle_directory("src")
  MiniTest.expect.equality(file_tree.is_expanded("src"), false)
end

T["directory expansion"]["toggle_directory expands collapsed dir"] = function()
  file_tree.toggle_directory("src")
  MiniTest.expect.equality(file_tree.is_expanded("src"), false)
  file_tree.toggle_directory("src")
  MiniTest.expect.equality(file_tree.is_expanded("src"), true)
end

T["directory expansion"]["collapse_all collapses all directories"] = function()
  file_tree.collapse_all()
  MiniTest.expect.equality(file_tree.is_expanded(""), false)
  MiniTest.expect.equality(file_tree.is_expanded("src"), false)
  MiniTest.expect.equality(file_tree.is_expanded("tests"), false)
end

T["directory expansion"]["expand_all expands all directories"] = function()
  file_tree.collapse_all()
  file_tree.expand_all()
  MiniTest.expect.equality(file_tree.is_expanded(""), true)
  MiniTest.expect.equality(file_tree.is_expanded("src"), true)
  MiniTest.expect.equality(file_tree.is_expanded("tests"), true)
end

T["directory expansion"]["collapsed dir hides files from selectable items"] = function()
  -- All expanded: 4 files selectable
  MiniTest.expect.equality(#file_tree.get_sorted_paths(), 4)

  -- Collapse src: should hide 2 files
  file_tree.toggle_directory("src")
  MiniTest.expect.equality(#file_tree.get_sorted_paths(), 2)
end

T["directory expansion"]["select_by_path auto-expands collapsed dir"] = function()
  file_tree.toggle_directory("src")
  MiniTest.expect.equality(file_tree.is_expanded("src"), false)

  -- Select a file in collapsed dir
  file_tree.select_by_path("src/main.lua")

  -- Should auto-expand
  MiniTest.expect.equality(file_tree.is_expanded("src"), true)
end

return T
