-- Tests for review.ui.diff module
local T = MiniTest.new_set()

local diff = require("review.ui.diff")
local state = require("review.core.state")
local config = require("review.config")
local layout = require("review.ui.layout")

-- Helper to clean up after tests
local function cleanup()
  pcall(function()
    diff.cleanup()
  end)
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
end

-- =============================================================================
-- find_file()
-- =============================================================================
T["find_file()"] = MiniTest.new_set({
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

T["find_file()"]["returns file when found"] = function()
  state.add_file({
    path = "src/main.lua",
    status = "modified",
    additions = 10,
    deletions = 5,
    comment_count = 0,
    hunks = {},
  })

  local file = diff.find_file("src/main.lua")
  MiniTest.expect.no_equality(file, nil)
  MiniTest.expect.equality(file.path, "src/main.lua")
end

T["find_file()"]["returns nil when not found"] = function()
  state.add_file({
    path = "src/main.lua",
    status = "modified",
    additions = 10,
    deletions = 5,
    comment_count = 0,
    hunks = {},
  })

  local file = diff.find_file("nonexistent.lua")
  MiniTest.expect.equality(file, nil)
end

T["find_file()"]["returns nil when no files"] = function()
  local file = diff.find_file("any.lua")
  MiniTest.expect.equality(file, nil)
end

-- =============================================================================
-- get_base_ref()
-- =============================================================================
T["get_base_ref()"] = MiniTest.new_set({
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

T["get_base_ref()"]["returns HEAD by default"] = function()
  local base = diff.get_base_ref()
  MiniTest.expect.equality(base, "HEAD")
end

T["get_base_ref()"]["returns configured base ref"] = function()
  state.set_mode("local", { base = "main" })
  local base = diff.get_base_ref()
  MiniTest.expect.equality(base, "main")
end

T["get_base_ref()"]["returns PR base for PR mode"] = function()
  state.set_mode("pr", {
    pr = {
      number = 123,
      title = "Test PR",
      description = "",
      author = "user",
      branch = "feature",
      base = "develop",
      created_at = "2024-01-01T00:00:00Z",
      updated_at = "2024-01-01T00:00:00Z",
      additions = 10,
      deletions = 5,
      changed_files = 1,
      state = "open",
      url = "https://github.com/test/test/pull/123",
    },
  })

  local base = diff.get_base_ref()
  MiniTest.expect.equality(base, "develop")
end

-- =============================================================================
-- get_head_ref()
-- =============================================================================
T["get_head_ref()"] = MiniTest.new_set({
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

T["get_head_ref()"]["returns nil for local mode"] = function()
  state.set_mode("local")
  local head = diff.get_head_ref()
  MiniTest.expect.equality(head, nil)
end

T["get_head_ref()"]["returns branch for remote PR mode"] = function()
  state.set_mode("pr", {
    pr_mode = "remote",
    pr = {
      number = 123,
      title = "Test PR",
      description = "",
      author = "user",
      branch = "feature-branch",
      base = "main",
      created_at = "2024-01-01T00:00:00Z",
      updated_at = "2024-01-01T00:00:00Z",
      additions = 10,
      deletions = 5,
      changed_files = 1,
      state = "open",
      url = "https://github.com/test/test/pull/123",
    },
  })

  local head = diff.get_head_ref()
  MiniTest.expect.equality(head, "feature-branch")
end

T["get_head_ref()"]["returns nil for local PR mode"] = function()
  state.set_mode("pr", {
    pr_mode = "local",
    pr = {
      number = 123,
      title = "Test PR",
      description = "",
      author = "user",
      branch = "feature-branch",
      base = "main",
      created_at = "2024-01-01T00:00:00Z",
      updated_at = "2024-01-01T00:00:00Z",
      additions = 10,
      deletions = 5,
      changed_files = 1,
      state = "open",
      url = "https://github.com/test/test/pull/123",
    },
  })

  local head = diff.get_head_ref()
  MiniTest.expect.equality(head, nil)
end

-- =============================================================================
-- is_diff_mode()
-- =============================================================================
T["is_diff_mode()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["is_diff_mode()"]["returns false initially"] = function()
  MiniTest.expect.equality(diff.is_diff_mode(), false)
end

-- =============================================================================
-- open_file() - basic tests
-- =============================================================================
T["open_file()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["open_file()"]["returns false when review not active"] = function()
  local success = diff.open_file("test.lua")
  MiniTest.expect.equality(success, false)
end

T["open_file()"]["sets current file in state"] = function()
  layout.open()

  -- Use an "added" file so it doesn't need git.show_file
  state.add_file({
    path = "test.lua",
    status = "added",
    additions = 1,
    deletions = 0,
    comment_count = 0,
    hunks = {},
  })

  -- Create a temp file to edit
  local tmp = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "-- test content" }, tmp)

  -- Open the temp file as "test.lua" in state
  state.state.files[1].path = tmp

  diff.open_file(tmp)

  MiniTest.expect.equality(state.state.current_file, tmp)

  -- Cleanup temp file
  vim.fn.delete(tmp)
end

-- =============================================================================
-- setup_diff_window_options()
-- =============================================================================
T["setup_diff_window_options()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["setup_diff_window_options()"]["sets correct window options"] = function()
  local win = layout.get_diff_win()
  diff.setup_diff_window_options(win)

  MiniTest.expect.equality(vim.wo[win].wrap, false)
  MiniTest.expect.equality(vim.wo[win].cursorline, true)
  MiniTest.expect.equality(vim.wo[win].foldmethod, "diff")
  MiniTest.expect.equality(vim.wo[win].foldlevel, 99)
end

T["setup_diff_window_options()"]["handles invalid window"] = function()
  -- Should not error
  diff.setup_diff_window_options(nil)
  diff.setup_diff_window_options(99999)
end

-- =============================================================================
-- get_current_buf() / get_old_buf()
-- =============================================================================
T["get_current_buf()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_current_buf()"]["returns nil when no diff open"] = function()
  local buf = diff.get_current_buf()
  MiniTest.expect.equality(buf, nil)
end

T["get_old_buf()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_old_buf()"]["returns nil when no diff open"] = function()
  local buf = diff.get_old_buf()
  MiniTest.expect.equality(buf, nil)
end

-- =============================================================================
-- close_diff_buffers()
-- =============================================================================
T["close_diff_buffers()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["close_diff_buffers()"]["does not error when no buffers"] = function()
  -- Should not error
  diff.close_diff_buffers()
end

-- =============================================================================
-- get_cursor_line()
-- =============================================================================
T["get_cursor_line()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_cursor_line()"]["returns current line number"] = function()
  local win = layout.get_diff_win()
  vim.api.nvim_set_current_win(win)

  -- Create a buffer with some content
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3" })
  vim.api.nvim_win_set_buf(win, buf)

  vim.api.nvim_win_set_cursor(win, { 2, 0 })
  local line = diff.get_cursor_line()
  MiniTest.expect.equality(line, 2)
end

T["get_cursor_line()"]["returns nil when no diff window"] = function()
  cleanup()
  local line = diff.get_cursor_line()
  MiniTest.expect.equality(line, nil)
end

-- =============================================================================
-- goto_line()
-- =============================================================================
T["goto_line()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
      layout.open()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["goto_line()"]["moves cursor to specified line"] = function()
  local win = layout.get_diff_win()
  vim.api.nvim_set_current_win(win)

  -- Create a buffer with content
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2", "line 3", "line 4", "line 5" })
  vim.api.nvim_win_set_buf(win, buf)
  state.state.layout.diff_buf = buf

  diff.goto_line(3)

  local cursor = vim.api.nvim_win_get_cursor(win)
  MiniTest.expect.equality(cursor[1], 3)
end

T["goto_line()"]["clamps to valid line numbers"] = function()
  local win = layout.get_diff_win()
  vim.api.nvim_set_current_win(win)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })
  vim.api.nvim_win_set_buf(win, buf)
  state.state.layout.diff_buf = buf

  -- Should not error for out of range
  diff.goto_line(100)
  diff.goto_line(0)
  diff.goto_line(-1)
end

-- =============================================================================
-- next_hunk() / prev_hunk()
-- =============================================================================
T["next_hunk()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["next_hunk()"]["does not error when not in diff mode"] = function()
  -- Should not error
  diff.next_hunk()
end

T["prev_hunk()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["prev_hunk()"]["does not error when not in diff mode"] = function()
  -- Should not error
  diff.prev_hunk()
end

-- =============================================================================
-- get_hunk_at_cursor()
-- =============================================================================
T["get_hunk_at_cursor()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["get_hunk_at_cursor()"]["returns nil when no current file"] = function()
  local hunk = diff.get_hunk_at_cursor()
  MiniTest.expect.equality(hunk, nil)
end

T["get_hunk_at_cursor()"]["returns nil when file has no hunks"] = function()
  layout.open()
  state.state.current_file = "test.lua"
  state.add_file({
    path = "test.lua",
    status = "modified",
    additions = 1,
    deletions = 0,
    comment_count = 0,
    hunks = {},
  })

  local hunk = diff.get_hunk_at_cursor()
  MiniTest.expect.equality(hunk, nil)
end

T["get_hunk_at_cursor()"]["finds hunk containing cursor line"] = function()
  layout.open()
  state.state.current_file = "test.lua"
  state.add_file({
    path = "test.lua",
    status = "modified",
    additions = 1,
    deletions = 0,
    comment_count = 0,
    hunks = {
      {
        old_start = 1,
        old_count = 3,
        new_start = 1,
        new_count = 4,
        header = "@@ -1,3 +1,4 @@",
        lines = {
          { type = "context", content = "line 1", old_line = 1, new_line = 1 },
          { type = "add", content = "new line", new_line = 2 },
          { type = "context", content = "line 2", old_line = 2, new_line = 3 },
          { type = "context", content = "line 3", old_line = 3, new_line = 4 },
        },
      },
    },
  })

  local win = layout.get_diff_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "new line", "line 2", "line 3" })
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, { 2, 0 })

  local hunk = diff.get_hunk_at_cursor()
  MiniTest.expect.no_equality(hunk, nil)
  MiniTest.expect.equality(hunk.new_start, 1)
end

-- =============================================================================
-- setup_autocmds() / cleanup_autocmds()
-- =============================================================================
T["setup_autocmds()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["setup_autocmds()"]["creates augroup"] = function()
  diff.setup_autocmds()
  -- Should not error when called again
  diff.setup_autocmds()
  -- Cleanup
  diff.cleanup_autocmds()
end

T["cleanup_autocmds()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["cleanup_autocmds()"]["removes augroup"] = function()
  diff.setup_autocmds()
  -- Should not error
  diff.cleanup_autocmds()
  -- Should not error when called again
  diff.cleanup_autocmds()
end

-- =============================================================================
-- cleanup()
-- =============================================================================
T["cleanup()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["cleanup()"]["does not error when no state"] = function()
  -- Should not error
  diff.cleanup()
end

-- =============================================================================
-- refresh()
-- =============================================================================
T["refresh()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["refresh()"]["does not error when no current file"] = function()
  -- Should not error
  diff.refresh()
end

T["refresh()"]["does not error when current file set"] = function()
  layout.open()
  state.state.current_file = "test.lua"
  -- Should not error
  diff.refresh()
end

-- =============================================================================
-- refresh_decorations()
-- =============================================================================
T["refresh_decorations()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["refresh_decorations()"]["does not error"] = function()
  -- Should not error even when modules don't exist
  diff.refresh_decorations()
end

-- =============================================================================
-- create_ref_buffer()
-- =============================================================================
T["create_ref_buffer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
      cleanup()
    end,
    post_case = function()
      cleanup()
    end,
  },
})

T["create_ref_buffer()"]["returns nil when git.show_file fails"] = function()
  -- Reload diff to ensure it has correct git reference after any previous test pollution
  package.loaded["review.ui.diff"] = nil
  local diff_mod = require("review.ui.diff")

  -- Mock git.show_file to return nil (file not found)
  local git = require("review.integrations.git")
  local original_show_file = git.show_file
  git.show_file = function()
    return nil
  end

  local buf = diff_mod.create_ref_buffer("nonexistent/path.lua", "HEAD")
  MiniTest.expect.equality(buf, nil)

  -- Restore
  git.show_file = original_show_file
end

T["create_ref_buffer()"]["creates buffer with file content"] = function()
  -- Reload diff to ensure it has correct git reference after any previous test pollution
  package.loaded["review.ui.diff"] = nil
  local diff_mod = require("review.ui.diff")

  local git = require("review.integrations.git")
  local original_show_file = git.show_file
  git.show_file = function()
    return "line 1\nline 2\nline 3"
  end

  local buf = diff_mod.create_ref_buffer("test.lua", "HEAD")
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), true)

  -- Check content
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)
  MiniTest.expect.equality(lines[1], "line 1")

  -- Check buffer options
  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")
  MiniTest.expect.equality(vim.bo[buf].modifiable, false)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
  git.show_file = original_show_file
end

T["create_ref_buffer()"]["creates editable buffer when readonly=false"] = function()
  -- Reload diff to ensure it has correct git reference after any previous test pollution
  package.loaded["review.ui.diff"] = nil
  local diff_mod = require("review.ui.diff")

  local git = require("review.integrations.git")
  local original_show_file = git.show_file
  git.show_file = function()
    return "content"
  end

  local buf = diff_mod.create_ref_buffer("test.lua", "HEAD", { readonly = false })
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.bo[buf].modifiable, true)

  -- Cleanup
  vim.api.nvim_buf_delete(buf, { force = true })
  git.show_file = original_show_file
end

return T
