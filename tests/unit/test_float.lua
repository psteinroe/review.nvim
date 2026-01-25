-- Tests for review.ui.float module
local T = MiniTest.new_set()

local float = require("review.ui.float")

-- Helper to get config module
local function get_config()
  return package.loaded["review.config"] or require("review.config")
end

-- Helper to create a test comment
local function make_comment(opts)
  opts = opts or {}
  return {
    id = opts.id or "test_" .. math.random(10000),
    kind = opts.kind or "local",
    body = opts.body or "Test comment",
    author = opts.author or "you",
    created_at = opts.created_at or "2025-01-01T00:00:00Z",
    file = opts.file or "test.lua",
    line = opts.line or 1,
    type = opts.type,
    resolved = opts.resolved,
    status = opts.status or "pending",
    replies = opts.replies,
  }
end

-- Cleanup all floating windows and buffers after each test
local function cleanup_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and float.is_float(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buftype = vim.bo[buf].buftype
      if buftype == "nofile" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

-- ============================================================================
-- get_namespace()
-- ============================================================================
T["get_namespace()"] = MiniTest.new_set()

T["get_namespace()"]["returns a valid namespace id"] = function()
  local ns = float.get_namespace()
  MiniTest.expect.equality(type(ns), "number")
  MiniTest.expect.equality(ns > 0, true)
end

-- ============================================================================
-- calculate_width()
-- ============================================================================
T["calculate_width()"] = MiniTest.new_set()

T["calculate_width()"]["returns minimum width for empty lines"] = function()
  local width = float.calculate_width({})
  -- Should return at least min_width (default 20)
  MiniTest.expect.equality(width >= 20, true)
end

T["calculate_width()"]["respects maximum width"] = function()
  local long_line = string.rep("x", 200)
  local width = float.calculate_width({ long_line }, 80)
  MiniTest.expect.equality(width, 80)
end

T["calculate_width()"]["calculates width based on longest line"] = function()
  local lines = { "short", "this is a longer line", "medium" }
  local width = float.calculate_width(lines, 100, 10)
  -- "this is a longer line" = 21 chars + 2 padding = 23
  MiniTest.expect.equality(width >= 21, true)
end

T["calculate_width()"]["respects custom min_width"] = function()
  local width = float.calculate_width({ "hi" }, 100, 30)
  MiniTest.expect.equality(width, 30)
end

-- ============================================================================
-- calculate_height()
-- ============================================================================
T["calculate_height()"] = MiniTest.new_set()

T["calculate_height()"]["returns minimum height for empty lines"] = function()
  local height = float.calculate_height({})
  -- Should return min_height (default 3)
  MiniTest.expect.equality(height >= 3, true)
end

T["calculate_height()"]["returns line count within limits"] = function()
  local lines = { "1", "2", "3", "4", "5" }
  local height = float.calculate_height(lines, 10, 1)
  MiniTest.expect.equality(height, 5)
end

T["calculate_height()"]["respects maximum height"] = function()
  local lines = {}
  for i = 1, 100 do
    table.insert(lines, tostring(i))
  end
  local height = float.calculate_height(lines, 40)
  MiniTest.expect.equality(height, 40)
end

T["calculate_height()"]["respects custom min_height"] = function()
  local height = float.calculate_height({ "one" }, 100, 5)
  MiniTest.expect.equality(height, 5)
end

-- ============================================================================
-- calculate_position()
-- ============================================================================
T["calculate_position()"] = MiniTest.new_set()

T["calculate_position()"]["returns position object with row and col"] = function()
  local pos = float.calculate_position(40, 10)
  MiniTest.expect.equality(type(pos), "table")
  MiniTest.expect.equality(type(pos.row), "number")
  MiniTest.expect.equality(type(pos.col), "number")
end

-- ============================================================================
-- create()
-- ============================================================================
T["create()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["create()"]["creates a floating window"] = function()
  local win, buf = float.create({ "Hello", "World" })

  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), true)
end

T["create()"]["sets buffer content correctly"] = function()
  local lines = { "line 1", "line 2", "line 3" }
  local win, buf = float.create(lines)

  local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(content, lines)
end

T["create()"]["creates floating window with correct relative type"] = function()
  local win, _ = float.create({ "test" })

  local config = vim.api.nvim_win_get_config(win)
  MiniTest.expect.no_equality(config.relative, "")
end

T["create()"]["respects custom width and height"] = function()
  local win, _ = float.create({ "test" }, { width = 50, height = 15 })

  MiniTest.expect.equality(vim.api.nvim_win_get_width(win), 50)
  MiniTest.expect.equality(vim.api.nvim_win_get_height(win), 15)
end

T["create()"]["sets buffer type to nofile"] = function()
  local _, buf = float.create({ "test" })

  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")
end

T["create()"]["sets filetype when provided"] = function()
  local _, buf = float.create({ "test" }, { filetype = "markdown" })

  MiniTest.expect.equality(vim.bo[buf].filetype, "markdown")
end

T["create()"]["makes buffer non-modifiable when specified"] = function()
  local _, buf = float.create({ "test" }, { modifiable = false })

  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
end

T["create()"]["enters window by default"] = function()
  local win, _ = float.create({ "test" })

  MiniTest.expect.equality(vim.api.nvim_get_current_win(), win)
end

T["create()"]["does not enter window when enter=false"] = function()
  local current_win = vim.api.nvim_get_current_win()
  local win, _ = float.create({ "test" }, { enter = false })

  MiniTest.expect.no_equality(vim.api.nvim_get_current_win(), win)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), current_win)
end

T["create()"]["sets window title when provided"] = function()
  local win, _ = float.create({ "test" }, { title = "My Title" })

  local config = vim.api.nvim_win_get_config(win)
  -- Title is returned as nested table: { { " My Title " } }
  MiniTest.expect.no_equality(config.title, nil)
  -- Check that title contains our text
  local title_text = config.title[1][1]
  MiniTest.expect.equality(title_text, " My Title ")
end

-- ============================================================================
-- close()
-- ============================================================================
T["close()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["close()"]["closes a valid floating window"] = function()
  local win, _ = float.create({ "test" })
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)

  float.close(win)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), false)
end

T["close()"]["handles nil window gracefully"] = function()
  -- Should not error
  float.close(nil)
end

T["close()"]["handles invalid window gracefully"] = function()
  -- Should not error
  float.close(99999)
end

-- ============================================================================
-- is_float()
-- ============================================================================
T["is_float()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["is_float()"]["returns true for floating windows"] = function()
  local win, _ = float.create({ "test" }, { enter = false })

  MiniTest.expect.equality(float.is_float(win), true)
end

T["is_float()"]["returns false for regular windows"] = function()
  local current_win = vim.api.nvim_get_current_win()
  MiniTest.expect.equality(float.is_float(current_win), false)
end

T["is_float()"]["returns false for nil"] = function()
  MiniTest.expect.equality(float.is_float(nil), false)
end

T["is_float()"]["returns false for invalid window"] = function()
  MiniTest.expect.equality(float.is_float(99999), false)
end

-- ============================================================================
-- get_comment_icon()
-- ============================================================================
T["get_comment_icon()"] = MiniTest.new_set()

T["get_comment_icon()"]["returns checkmark for resolved comments"] = function()
  local comment = make_comment({ resolved = true })
  MiniTest.expect.equality(float.get_comment_icon(comment), "✓")
end

T["get_comment_icon()"]["returns speech bubble for review comments"] = function()
  local comment = make_comment({ kind = "review" })
  MiniTest.expect.equality(float.get_comment_icon(comment), "💬")
end

T["get_comment_icon()"]["returns pencil for local note comments"] = function()
  local comment = make_comment({ kind = "local", type = "note" })
  MiniTest.expect.equality(float.get_comment_icon(comment), "📝")
end

T["get_comment_icon()"]["returns warning for issue comments"] = function()
  local comment = make_comment({ kind = "local", type = "issue" })
  MiniTest.expect.equality(float.get_comment_icon(comment), "⚠️")
end

T["get_comment_icon()"]["returns lightbulb for suggestion comments"] = function()
  local comment = make_comment({ kind = "local", type = "suggestion" })
  MiniTest.expect.equality(float.get_comment_icon(comment), "💡")
end

T["get_comment_icon()"]["returns sparkle for praise comments"] = function()
  local comment = make_comment({ kind = "local", type = "praise" })
  MiniTest.expect.equality(float.get_comment_icon(comment), "✨")
end

-- ============================================================================
-- format_comment()
-- ============================================================================
T["format_comment()"] = MiniTest.new_set()

T["format_comment()"]["returns array of lines"] = function()
  local comment = make_comment()
  local lines = float.format_comment(comment)

  MiniTest.expect.equality(type(lines), "table")
  MiniTest.expect.equality(#lines > 0, true)
end

T["format_comment()"]["includes author in header"] = function()
  local comment = make_comment({ author = "testuser" })
  local lines = float.format_comment(comment)

  local header = lines[1]
  MiniTest.expect.equality(header:find("@testuser") ~= nil, true)
end

T["format_comment()"]["includes comment body"] = function()
  local comment = make_comment({ body = "This is the comment body" })
  local lines = float.format_comment(comment)

  local found_body = false
  for _, line in ipairs(lines) do
    if line:find("This is the comment body") then
      found_body = true
      break
    end
  end
  MiniTest.expect.equality(found_body, true)
end

T["format_comment()"]["handles multi-line body"] = function()
  local comment = make_comment({ body = "Line 1\nLine 2\nLine 3" })
  local lines = float.format_comment(comment)

  local line_count = 0
  for _, line in ipairs(lines) do
    if line == "Line 1" or line == "Line 2" or line == "Line 3" then
      line_count = line_count + 1
    end
  end
  MiniTest.expect.equality(line_count, 3)
end

T["format_comment()"]["handles empty body"] = function()
  local comment = make_comment({ body = "" })
  local lines = float.format_comment(comment)

  local found_placeholder = false
  for _, line in ipairs(lines) do
    if line:find("no content") then
      found_placeholder = true
      break
    end
  end
  MiniTest.expect.equality(found_placeholder, true)
end

T["format_comment()"]["includes replies when present"] = function()
  local comment = make_comment({
    replies = {
      { author = "replier", body = "This is a reply" },
    },
  })
  local lines = float.format_comment(comment)

  local found_reply = false
  for _, line in ipairs(lines) do
    if line:find("@replier") and line:find("This is a reply") then
      found_reply = true
      break
    end
  end
  MiniTest.expect.equality(found_reply, true)
end

T["format_comment()"]["shows edit/delete actions for local comments"] = function()
  local comment = make_comment({ kind = "local" })
  local lines = float.format_comment(comment)

  local found_actions = false
  for _, line in ipairs(lines) do
    if line:find("%[e%]dit") and line:find("%[d%]elete") then
      found_actions = true
      break
    end
  end
  MiniTest.expect.equality(found_actions, true)
end

T["format_comment()"]["shows reply/resolve actions for review comments"] = function()
  local comment = make_comment({ kind = "review" })
  local lines = float.format_comment(comment)

  local found_actions = false
  for _, line in ipairs(lines) do
    if line:find("%[r%]eply") and line:find("%[R%]esolve") then
      found_actions = true
      break
    end
  end
  MiniTest.expect.equality(found_actions, true)
end

-- ============================================================================
-- show_comment()
-- ============================================================================
T["show_comment()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["show_comment()"]["creates a floating window"] = function()
  local comment = make_comment()
  local win, buf = float.show_comment(comment)

  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(buf), true)
end

T["show_comment()"]["does not enter the window"] = function()
  local current_win = vim.api.nvim_get_current_win()
  local comment = make_comment()
  local win, _ = float.show_comment(comment)

  MiniTest.expect.no_equality(win, current_win)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), current_win)
end

T["show_comment()"]["sets filetype to markdown"] = function()
  local comment = make_comment()
  local _, buf = float.show_comment(comment)

  MiniTest.expect.equality(vim.bo[buf].filetype, "markdown")
end

-- ============================================================================
-- update_content()
-- ============================================================================
T["update_content()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["update_content()"]["updates buffer content"] = function()
  local win, buf = float.create({ "original" })

  local success = float.update_content(win, { "updated", "content" })
  MiniTest.expect.equality(success, true)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines, { "updated", "content" })
end

T["update_content()"]["returns false for invalid window"] = function()
  local success = float.update_content(99999, { "test" })
  MiniTest.expect.equality(success, false)
end

T["update_content()"]["returns false for nil window"] = function()
  local success = float.update_content(nil, { "test" })
  MiniTest.expect.equality(success, false)
end

T["update_content()"]["preserves modifiable state"] = function()
  local win, buf = float.create({ "original" }, { modifiable = false })

  float.update_content(win, { "updated" })

  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
end

-- ============================================================================
-- resize()
-- ============================================================================
T["resize()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["resize()"]["changes window dimensions"] = function()
  local win, _ = float.create({ "test" }, { width = 30, height = 10 })

  local success = float.resize(win, 50, 20)
  MiniTest.expect.equality(success, true)

  MiniTest.expect.equality(vim.api.nvim_win_get_width(win), 50)
  MiniTest.expect.equality(vim.api.nvim_win_get_height(win), 20)
end

T["resize()"]["returns false for invalid window"] = function()
  local success = float.resize(99999, 50, 20)
  MiniTest.expect.equality(success, false)
end

T["resize()"]["returns false for nil window"] = function()
  local success = float.resize(nil, 50, 20)
  MiniTest.expect.equality(success, false)
end

-- ============================================================================
-- input() - basic test (uses vim.ui.input which is hard to fully test)
-- ============================================================================
T["input()"] = MiniTest.new_set()

T["input()"]["calls callback when vim.ui.input completes"] = function()
  -- Mock vim.ui.input
  local original_input = vim.ui.input
  local captured_opts = nil
  local captured_callback = nil

  vim.ui.input = function(opts, callback)
    captured_opts = opts
    captured_callback = callback
  end

  float.input("Enter text:", { default = "default" }, function(_) end)

  MiniTest.expect.equality(captured_opts.prompt, "Enter text:")
  MiniTest.expect.equality(captured_opts.default, "default")
  MiniTest.expect.no_equality(captured_callback, nil)

  -- Restore
  vim.ui.input = original_input
end

-- ============================================================================
-- confirm() - basic structure test
-- ============================================================================
T["confirm()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["confirm()"]["creates a floating window with prompt"] = function()
  local float_created = false
  local callback_result = nil

  float.confirm("Are you sure?", function(result)
    callback_result = result
  end)

  -- Find the floating window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if float.is_float(win) then
      float_created = true
      local buf = vim.api.nvim_win_get_buf(win)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- Check that prompt is in content
      local found_prompt = false
      for _, line in ipairs(lines) do
        if line:find("Are you sure") then
          found_prompt = true
          break
        end
      end
      MiniTest.expect.equality(found_prompt, true)
      break
    end
  end

  MiniTest.expect.equality(float_created, true)
end

-- ============================================================================
-- menu() - basic test (uses vim.ui.select)
-- ============================================================================
T["menu()"] = MiniTest.new_set()

T["menu()"]["calls callback with nil for empty items"] = function()
  local callback_called = false
  local callback_result = "not_nil"

  float.menu({}, {
    callback = function(choice)
      callback_called = true
      callback_result = choice
    end,
  })

  MiniTest.expect.equality(callback_called, true)
  MiniTest.expect.equality(callback_result, nil)
end

T["menu()"]["calls vim.ui.select with items"] = function()
  -- Mock vim.ui.select
  local original_select = vim.ui.select
  local captured_items = nil

  vim.ui.select = function(items, _, _)
    captured_items = items
  end

  float.menu({ "Option 1", "Option 2" }, {
    prompt = "Choose:",
    callback = function(_) end,
  })

  MiniTest.expect.equality(captured_items, { "Option 1", "Option 2" })

  -- Restore
  vim.ui.select = original_select
end

-- ============================================================================
-- notify() - basic test
-- ============================================================================
T["notify()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = cleanup_floats,
  },
})

T["notify()"]["creates a floating window"] = function()
  local win = float.notify("Test message")

  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), true)
  MiniTest.expect.equality(float.is_float(win), true)
end

T["notify()"]["handles string message"] = function()
  local win = float.notify("Single line message")

  MiniTest.expect.no_equality(win, nil)
end

T["notify()"]["handles array message"] = function()
  local win = float.notify({ "Line 1", "Line 2" })

  MiniTest.expect.no_equality(win, nil)
end

T["notify()"]["includes icon based on level"] = function()
  local win = float.notify("Warning", { level = "warn" })

  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Check for warning icon
  local found_icon = false
  for _, line in ipairs(lines) do
    if line:find("⚠️") then
      found_icon = true
      break
    end
  end
  MiniTest.expect.equality(found_icon, true)
end

return T
