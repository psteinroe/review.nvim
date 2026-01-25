-- Tests for review.ui.file_tree module
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
    },
    {
      path = "src/utils.lua",
      status = "added",
      additions = 50,
      deletions = 0,
      comment_count = 0,
      hunks = {},
    },
    {
      path = "tests/test_main.lua",
      status = "modified",
      additions = 5,
      deletions = 2,
      comment_count = 1,
      hunks = {},
    },
    {
      path = "README.md",
      status = "modified",
      additions = 3,
      deletions = 1,
      comment_count = 0,
      hunks = {},
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
-- get_status_icon tests
-- ============================================================================

T["get_status_icon()"] = MiniTest.new_set()

T["get_status_icon()"]["returns + for added files"] = function()
  config.setup()
  local icon, hl = file_tree.get_status_icon("added")
  MiniTest.expect.equality(icon, "+")
  MiniTest.expect.equality(hl, "ReviewTreeAdded")
end

T["get_status_icon()"]["returns ~ for modified files"] = function()
  config.setup()
  local icon, hl = file_tree.get_status_icon("modified")
  MiniTest.expect.equality(icon, "~")
  MiniTest.expect.equality(hl, "ReviewTreeModified")
end

T["get_status_icon()"]["returns - for deleted files"] = function()
  config.setup()
  local icon, hl = file_tree.get_status_icon("deleted")
  MiniTest.expect.equality(icon, "-")
  MiniTest.expect.equality(hl, "ReviewTreeDeleted")
end

T["get_status_icon()"]["returns R for renamed files"] = function()
  config.setup()
  local icon, hl = file_tree.get_status_icon("renamed")
  MiniTest.expect.equality(icon, "R")
  MiniTest.expect.equality(hl, "ReviewTreeRenamed")
end

T["get_status_icon()"]["returns ? for unknown status"] = function()
  config.setup()
  local icon, hl = file_tree.get_status_icon("unknown")
  MiniTest.expect.equality(icon, "?")
  MiniTest.expect.equality(hl, "ReviewTreeFile")
end

-- ============================================================================
-- build_tree tests
-- ============================================================================

T["build_tree()"] = MiniTest.new_set()

T["build_tree()"]["returns empty table for empty files"] = function()
  local tree = file_tree.build_tree({})
  MiniTest.expect.equality(vim.tbl_count(tree), 0)
end

T["build_tree()"]["creates file nodes for flat paths"] = function()
  local files = {
    { path = "README.md", status = "modified" },
    { path = "LICENSE", status = "added" },
  }
  local tree = file_tree.build_tree(files)
  MiniTest.expect.no_equality(tree["README.md"], nil)
  MiniTest.expect.equality(tree["README.md"].type, "file")
  MiniTest.expect.no_equality(tree["LICENSE"], nil)
  MiniTest.expect.equality(tree["LICENSE"].type, "file")
end

T["build_tree()"]["creates directory nodes for nested paths"] = function()
  local files = {
    { path = "src/main.lua", status = "modified" },
  }
  local tree = file_tree.build_tree(files)
  MiniTest.expect.no_equality(tree["src"], nil)
  MiniTest.expect.equality(tree["src"].type, "dir")
  MiniTest.expect.no_equality(tree["src"].children["main.lua"], nil)
  MiniTest.expect.equality(tree["src"].children["main.lua"].type, "file")
end

T["build_tree()"]["handles multiple files in same directory"] = function()
  local files = {
    { path = "src/a.lua", status = "added" },
    { path = "src/b.lua", status = "modified" },
  }
  local tree = file_tree.build_tree(files)
  MiniTest.expect.equality(tree["src"].type, "dir")
  MiniTest.expect.no_equality(tree["src"].children["a.lua"], nil)
  MiniTest.expect.no_equality(tree["src"].children["b.lua"], nil)
end

T["build_tree()"]["handles deeply nested paths"] = function()
  local files = {
    { path = "a/b/c/d/file.lua", status = "modified" },
  }
  local tree = file_tree.build_tree(files)
  MiniTest.expect.equality(tree["a"].type, "dir")
  MiniTest.expect.equality(tree["a"].children["b"].type, "dir")
  MiniTest.expect.equality(tree["a"].children["b"].children["c"].type, "dir")
  MiniTest.expect.equality(tree["a"].children["b"].children["c"].children["d"].type, "dir")
  MiniTest.expect.equality(tree["a"].children["b"].children["c"].children["d"].children["file.lua"].type, "file")
end

T["build_tree()"]["stores file data in leaf nodes"] = function()
  local files = {
    { path = "test.lua", status = "modified", additions = 10, deletions = 5 },
  }
  local tree = file_tree.build_tree(files)
  MiniTest.expect.equality(tree["test.lua"].data.additions, 10)
  MiniTest.expect.equality(tree["test.lua"].data.deletions, 5)
end

-- ============================================================================
-- sort_tree_nodes tests
-- ============================================================================

T["sort_tree_nodes()"] = MiniTest.new_set()

T["sort_tree_nodes()"]["puts directories before files"] = function()
  local tree = {
    ["file.lua"] = { type = "file" },
    ["src"] = { type = "dir", children = {} },
  }
  local sorted = file_tree.sort_tree_nodes(tree)
  MiniTest.expect.equality(sorted[1].name, "src")
  MiniTest.expect.equality(sorted[2].name, "file.lua")
end

T["sort_tree_nodes()"]["sorts directories alphabetically"] = function()
  local tree = {
    ["zeta"] = { type = "dir", children = {} },
    ["alpha"] = { type = "dir", children = {} },
  }
  local sorted = file_tree.sort_tree_nodes(tree)
  MiniTest.expect.equality(sorted[1].name, "alpha")
  MiniTest.expect.equality(sorted[2].name, "zeta")
end

T["sort_tree_nodes()"]["sorts files alphabetically"] = function()
  local tree = {
    ["z.lua"] = { type = "file" },
    ["a.lua"] = { type = "file" },
  }
  local sorted = file_tree.sort_tree_nodes(tree)
  MiniTest.expect.equality(sorted[1].name, "a.lua")
  MiniTest.expect.equality(sorted[2].name, "z.lua")
end

T["sort_tree_nodes()"]["handles mixed directories and files"] = function()
  local tree = {
    ["z.lua"] = { type = "file" },
    ["src"] = { type = "dir", children = {} },
    ["a.lua"] = { type = "file" },
    ["lib"] = { type = "dir", children = {} },
  }
  local sorted = file_tree.sort_tree_nodes(tree)
  -- Directories first, alphabetically
  MiniTest.expect.equality(sorted[1].name, "lib")
  MiniTest.expect.equality(sorted[2].name, "src")
  -- Then files, alphabetically
  MiniTest.expect.equality(sorted[3].name, "a.lua")
  MiniTest.expect.equality(sorted[4].name, "z.lua")
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

T["render_header()"]["shows Review for local mode"] = function()
  state.state.mode = "local"
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[1], "Review (4 files)")
end

T["render_header()"]["shows PR info for pr mode"] = function()
  state.state.mode = "pr"
  state.state.pr = { number = 123, title = "Test PR" }
  state.state.files = create_test_files()
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[1], "PR #123 (4 files)")
end

T["render_header()"]["includes blank line separator"] = function()
  state.state.files = {}
  local lines, _ = file_tree.render_header()
  MiniTest.expect.equality(lines[2], "")
end

T["render_header()"]["adds header highlight"] = function()
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

T["render_footer()"]["shows comment counts"] = function()
  state.state.comments = {
    { id = "1", kind = "review", body = "test" },
    { id = "2", kind = "review", body = "test2" },
    { id = "3", kind = "local", body = "pending", status = "pending" },
  }
  local lines, _ = file_tree.render_footer()
  -- First line is blank separator
  MiniTest.expect.equality(lines[1], "")
  -- Contains comment count
  local found_comments = false
  local found_pending = false
  for _, line in ipairs(lines) do
    if line:match("2 comments") then
      found_comments = true
    end
    if line:match("1 pending") then
      found_pending = true
    end
  end
  MiniTest.expect.equality(found_comments, true)
  MiniTest.expect.equality(found_pending, true)
end

T["render_footer()"]["shows zero counts when no comments"] = function()
  state.state.comments = {}
  local lines, _ = file_tree.render_footer()
  local found_zero_comments = false
  local found_zero_pending = false
  for _, line in ipairs(lines) do
    if line:match("0 comments") then
      found_zero_comments = true
    end
    if line:match("0 pending") then
      found_zero_pending = true
    end
  end
  MiniTest.expect.equality(found_zero_comments, true)
  MiniTest.expect.equality(found_zero_pending, true)
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
  MiniTest.expect.equality(file.path, "src/utils.lua")
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
  MiniTest.expect.equality(file_tree.get_selected_idx(), 3)
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

T["render()"]["includes header line"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1]:match("Review"), "Review")
end

T["render()"]["includes file names"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  MiniTest.expect.equality(content:match("main.lua") ~= nil, true)
  MiniTest.expect.equality(content:match("utils.lua") ~= nil, true)
end

T["render()"]["includes directory names"] = function()
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  MiniTest.expect.equality(content:match("src/") ~= nil, true)
  MiniTest.expect.equality(content:match("tests/") ~= nil, true)
end

T["render()"]["includes comment counts"] = function()
  state.state.files[1].comment_count = 3
  file_tree.render()
  local buf = state.state.layout.file_tree_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  -- Should contain comment indicator
  MiniTest.expect.equality(content:match("#3") ~= nil or content:match("3") ~= nil, true)
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
  for _, km in ipairs(keymaps) do
    if km.lhs == "j" then
      has_j = true
    end
    if km.lhs == "<CR>" then
      has_cr = true
    end
  end
  MiniTest.expect.equality(has_j, true)
  MiniTest.expect.equality(has_cr, true)
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
    end,
    post_case = function()
      state.reset()
      file_tree.reset()
    end,
  },
})

T["open_selected()"]["sets current_file in state"] = function()
  file_tree.set_selected_idx(2)
  file_tree.open_selected()
  MiniTest.expect.equality(state.state.current_file, "src/utils.lua")
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
  file_tree.set_selected_idx(1)
  file_tree.open_selected()
  MiniTest.expect.no_equality(called_with, nil)
  MiniTest.expect.equality(called_with.path, "src/main.lua")
end

return T
