-- Tests for review.ui.virtual_text module
local T = MiniTest.new_set()

local virtual_text = require("review.ui.virtual_text")
local state = require("review.core.state")

-- IMPORTANT: We must use the config module from package.loaded to ensure
-- we're modifying the same instance that virtual_text uses internally.
-- MiniTest may load test files in a sandboxed environment which can cause
-- require() to return different module instances.
local function get_config()
  return package.loaded["review.config"] or require("review.config")
end

-- Helper to create a test buffer
local function create_test_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
    "line 6",
    "line 7",
    "line 8",
    "line 9",
    "line 10",
  })
  return buf
end

-- Helper to create a test comment
-- Use no_line = true to explicitly set line to nil
local function make_comment(opts)
  opts = opts or {}
  local line
  if opts.no_line then
    line = nil
  else
    line = opts.line or 1
  end
  return {
    id = opts.id or "test_" .. math.random(10000),
    kind = opts.kind or "local",
    body = opts.body or "Test comment",
    author = opts.author or "you",
    created_at = opts.created_at or "2025-01-01T00:00:00Z",
    file = opts.file or "test.lua",
    line = line,
    type = opts.type, -- note, issue, suggestion, praise
    resolved = opts.resolved,
    status = opts.status or "pending",
  }
end

-- Cleanup hooks
T["get_icon()"] = MiniTest.new_set()

T["get_icon()"]["returns checkmark for resolved comments"] = function()
  local comment = make_comment({ resolved = true })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "✓")
end

T["get_icon()"]["returns speech bubble for non-local comments"] = function()
  local comment = make_comment({ kind = "review" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "💬")
end

T["get_icon()"]["returns pencil for local note comments"] = function()
  local comment = make_comment({ kind = "local", type = "note" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "📝")
end

T["get_icon()"]["returns pencil for local comments without type"] = function()
  local comment = make_comment({ kind = "local" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "📝")
end

T["get_icon()"]["returns warning for local issue comments"] = function()
  local comment = make_comment({ kind = "local", type = "issue" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "⚠️")
end

T["get_icon()"]["returns lightbulb for local suggestion comments"] = function()
  local comment = make_comment({ kind = "local", type = "suggestion" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "💡")
end

T["get_icon()"]["returns sparkle for local praise comments"] = function()
  local comment = make_comment({ kind = "local", type = "praise" })
  MiniTest.expect.equality(virtual_text.get_icon(comment), "✨")
end

T["get_highlight()"] = MiniTest.new_set()

T["get_highlight()"]["returns resolved highlight for resolved comments"] = function()
  local comment = make_comment({ resolved = true })
  MiniTest.expect.equality(virtual_text.get_highlight(comment), "ReviewVirtualResolved")
end

T["get_highlight()"]["returns local highlight for local comments"] = function()
  local comment = make_comment({ kind = "local" })
  MiniTest.expect.equality(virtual_text.get_highlight(comment), "ReviewVirtualLocal")
end

T["get_highlight()"]["returns github highlight for github comments"] = function()
  local comment = make_comment({ kind = "review" })
  MiniTest.expect.equality(virtual_text.get_highlight(comment), "ReviewVirtualGithub")
end

T["truncate()"] = MiniTest.new_set()

T["truncate()"]["returns empty string for nil"] = function()
  MiniTest.expect.equality(virtual_text.truncate(nil, 20), "")
end

T["truncate()"]["returns text unchanged when under limit"] = function()
  MiniTest.expect.equality(virtual_text.truncate("short", 20), "short")
end

T["truncate()"]["truncates long text with ellipsis"] = function()
  local result = virtual_text.truncate("this is a very long text that should be truncated", 20)
  MiniTest.expect.equality(result, "this is a very lo...")
  MiniTest.expect.equality(#result, 20)
end

T["truncate()"]["replaces newlines with spaces"] = function()
  local result = virtual_text.truncate("line1\nline2\nline3", 50)
  MiniTest.expect.equality(result, "line1 line2 line3")
end

T["truncate()"]["collapses multiple spaces"] = function()
  local result = virtual_text.truncate("text   with   spaces", 50)
  MiniTest.expect.equality(result, "text with spaces")
end

T["truncate()"]["trims leading and trailing whitespace"] = function()
  local result = virtual_text.truncate("  trimmed  ", 50)
  MiniTest.expect.equality(result, "trimmed")
end

T["format_virtual_text()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
  },
})

T["format_virtual_text()"]["includes icon"] = function()
  local comment = make_comment({ kind = "local", type = "issue", body = "Fix this" })
  local text, _ = virtual_text.format_virtual_text(comment)
  MiniTest.expect.equality(text:find("⚠️") ~= nil, true)
end

T["format_virtual_text()"]["includes author for non-you authors"] = function()
  local comment = make_comment({ author = "reviewer", body = "Comment" })
  local text, _ = virtual_text.format_virtual_text(comment)
  MiniTest.expect.equality(text:find("@reviewer") ~= nil, true)
end

T["format_virtual_text()"]["excludes author when author is 'you'"] = function()
  local comment = make_comment({ author = "you", body = "Comment" })
  local text, _ = virtual_text.format_virtual_text(comment)
  MiniTest.expect.equality(text:find("@you") == nil, true)
end

T["format_virtual_text()"]["includes body preview"] = function()
  local comment = make_comment({ body = "This is the body" })
  local text, _ = virtual_text.format_virtual_text(comment)
  MiniTest.expect.equality(text:find("This is the body") ~= nil, true)
end

T["format_virtual_text()"]["returns correct highlight group"] = function()
  local comment = make_comment({ kind = "local" })
  local _, hl = virtual_text.format_virtual_text(comment)
  MiniTest.expect.equality(hl, "ReviewVirtualLocal")
end

T["format_virtual_text()"]["respects max_len parameter"] = function()
  local comment = make_comment({ body = "This is a very long comment body that should be truncated" })
  local text, _ = virtual_text.format_virtual_text(comment, 15)
  -- Icon + truncated text should be present
  MiniTest.expect.equality(text:find("...") ~= nil, true)
end

T["add_virtual_text()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["add_virtual_text()"]["adds extmark at correct line"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 5 })

  local extmark_id = virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.no_equality(extmark_id, nil)

  local extmarks = virtual_text.get_extmarks(buf)
  MiniTest.expect.equality(#extmarks, 1)
  MiniTest.expect.equality(extmarks[1][2], 4) -- 0-indexed
end

T["add_virtual_text()"]["returns nil for comment without line"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ no_line = true })

  local extmark_id = virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.equality(extmark_id, nil)
end

T["add_virtual_text()"]["returns nil for invalid buffer"] = function()
  local comment = make_comment({ line = 5 })
  local extmark_id = virtual_text.add_virtual_text(99999, comment)
  MiniTest.expect.equality(extmark_id, nil)
end

T["add_virtual_text()"]["returns nil for line out of range"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 100 }) -- Buffer only has 10 lines

  local extmark_id = virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.equality(extmark_id, nil)
end

T["add_virtual_text()"]["returns nil when virtual text is disabled"] = function()
  -- Use setup with explicit disabled setting
  get_config().setup({ virtual_text = { enabled = false } })

  local buf = create_test_buffer()
  local comment = make_comment({ line = 5 })

  local extmark_id = virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.equality(extmark_id, nil)
end

T["remove_virtual_text()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["remove_virtual_text()"]["removes extmark by id"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 5 })

  local extmark_id = virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)

  virtual_text.remove_virtual_text(buf, extmark_id)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)
end

T["remove_virtual_text()"]["handles invalid buffer gracefully"] = function()
  -- Should not error
  virtual_text.remove_virtual_text(99999, 1)
end

T["clear_buffer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["clear_buffer()"]["removes all virtual text from buffer"] = function()
  local buf = create_test_buffer()

  virtual_text.add_virtual_text(buf, make_comment({ line = 1 }))
  virtual_text.add_virtual_text(buf, make_comment({ line = 3 }))
  virtual_text.add_virtual_text(buf, make_comment({ line = 5 }))

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 3)

  virtual_text.clear_buffer(buf)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)
end

T["clear_buffer()"]["handles invalid buffer gracefully"] = function()
  -- Should not error
  virtual_text.clear_buffer(99999)
end

T["clear_all()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["clear_all()"]["removes virtual text from all buffers"] = function()
  local buf1 = create_test_buffer()
  local buf2 = create_test_buffer()

  virtual_text.add_virtual_text(buf1, make_comment({ line = 1 }))
  virtual_text.add_virtual_text(buf2, make_comment({ line = 2 }))

  MiniTest.expect.equality(virtual_text.count_extmarks(buf1), 1)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf2), 1)

  virtual_text.clear_all()

  MiniTest.expect.equality(virtual_text.count_extmarks(buf1), 0)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf2), 0)
end

T["refresh_buffer()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
      state.reset()
    end,
    post_case = function()
      state.reset()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["refresh_buffer()"]["adds virtual text for all file comments"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))
  state.add_comment(make_comment({ file = file, line = 3 }))
  state.add_comment(make_comment({ file = file, line = 5 }))

  virtual_text.refresh_buffer(buf, file)

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 3)
end

T["refresh_buffer()"]["clears old virtual text before adding new"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))

  virtual_text.refresh_buffer(buf, file)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)

  -- Clear comments and refresh
  state.reset()
  virtual_text.refresh_buffer(buf, file)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)
end

T["refresh_buffer()"]["ignores comments for other files"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))
  state.add_comment(make_comment({ file = "other.lua", line = 2 }))

  virtual_text.refresh_buffer(buf, file)

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)
end

T["refresh_buffer()"]["handles invalid buffer gracefully"] = function()
  state.set_current_file("test.lua")
  -- Should not error
  virtual_text.refresh_buffer(99999, "test.lua")
end

T["refresh_buffer()"]["uses current_file when file not provided"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 2 }))

  virtual_text.refresh_buffer(buf) -- No file argument

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)
end

T["refresh_buffer()"]["shows only one virtual text per line"] = function()
  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 3, body = "First" }))
  state.add_comment(make_comment({ file = file, line = 3, body = "Second" }))
  state.add_comment(make_comment({ file = file, line = 3, body = "Third" }))

  virtual_text.refresh_buffer(buf, file)

  -- Should only have one virtual text at line 3
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)
end

T["refresh_buffer()"]["does nothing when virtual text is disabled"] = function()
  -- Use setup with explicit disabled setting
  get_config().setup({ virtual_text = { enabled = false } })

  local buf = create_test_buffer()
  local file = "test.lua"

  state.set_current_file(file)
  state.add_comment(make_comment({ file = file, line = 1 }))

  virtual_text.refresh_buffer(buf, file)

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)
end

T["refresh()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
      state.reset()
    end,
    post_case = function()
      state.reset()
    end,
  },
})

T["refresh()"]["does nothing when no current file"] = function()
  -- Should not error
  virtual_text.refresh()
end

T["get_extmarks()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_extmarks()"]["returns all extmarks"] = function()
  local buf = create_test_buffer()

  virtual_text.add_virtual_text(buf, make_comment({ line = 1 }))
  virtual_text.add_virtual_text(buf, make_comment({ line = 5 }))

  local extmarks = virtual_text.get_extmarks(buf)
  MiniTest.expect.equality(#extmarks, 2)
end

T["get_extmarks()"]["returns empty table for buffer without extmarks"] = function()
  local buf = create_test_buffer()
  local extmarks = virtual_text.get_extmarks(buf)
  MiniTest.expect.equality(#extmarks, 0)
end

T["get_extmarks()"]["returns empty table for invalid buffer"] = function()
  local extmarks = virtual_text.get_extmarks(99999)
  MiniTest.expect.equality(#extmarks, 0)
end

T["get_extmark_at_line()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_extmark_at_line()"]["returns extmark at specified line"] = function()
  local buf = create_test_buffer()

  virtual_text.add_virtual_text(buf, make_comment({ line = 5 }))

  local extmark = virtual_text.get_extmark_at_line(buf, 5)
  MiniTest.expect.no_equality(extmark, nil)
  MiniTest.expect.equality(extmark[2], 4) -- 0-indexed
end

T["get_extmark_at_line()"]["returns nil when no extmark at line"] = function()
  local buf = create_test_buffer()

  virtual_text.add_virtual_text(buf, make_comment({ line = 5 }))

  local extmark = virtual_text.get_extmark_at_line(buf, 3)
  MiniTest.expect.equality(extmark, nil)
end

T["get_extmark_at_line()"]["returns nil for invalid buffer"] = function()
  local extmark = virtual_text.get_extmark_at_line(99999, 5)
  MiniTest.expect.equality(extmark, nil)
end

T["count_extmarks()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["count_extmarks()"]["returns correct count"] = function()
  local buf = create_test_buffer()

  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)

  virtual_text.add_virtual_text(buf, make_comment({ line = 1 }))
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)

  virtual_text.add_virtual_text(buf, make_comment({ line = 2 }))
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 2)
end

T["is_enabled()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Use setup to ensure clean state with enabled=true
      get_config().setup({ virtual_text = { enabled = true } })
    end,
  },
})

T["is_enabled()"]["returns true by default"] = function()
  MiniTest.expect.equality(virtual_text.is_enabled(), true)
end

T["is_enabled()"]["returns false when explicitly disabled"] = function()
  get_config().setup({ virtual_text = { enabled = false } })
  MiniTest.expect.equality(virtual_text.is_enabled(), false)
end

T["enable()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start with virtual text disabled via setup
      get_config().setup({ virtual_text = { enabled = false } })
    end,
  },
})

T["enable()"]["enables virtual text"] = function()
  MiniTest.expect.equality(virtual_text.is_enabled(), false)
  virtual_text.enable()
  MiniTest.expect.equality(virtual_text.is_enabled(), true)
end

T["disable()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start with virtual text enabled via setup
      get_config().setup({ virtual_text = { enabled = true } })
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["disable()"]["disables virtual text"] = function()
  MiniTest.expect.equality(virtual_text.is_enabled(), true)
  virtual_text.disable()
  MiniTest.expect.equality(virtual_text.is_enabled(), false)
end

T["disable()"]["clears all virtual text"] = function()
  local buf = create_test_buffer()
  virtual_text.add_virtual_text(buf, make_comment({ line = 1 }))
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)

  virtual_text.disable()
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 0)
end

T["toggle()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Start with virtual text enabled via setup
      get_config().setup({ virtual_text = { enabled = true } })
    end,
  },
})

T["toggle()"]["disables when enabled"] = function()
  MiniTest.expect.equality(virtual_text.is_enabled(), true)
  virtual_text.toggle()
  MiniTest.expect.equality(virtual_text.is_enabled(), false)
end

T["toggle()"]["enables when disabled"] = function()
  get_config().setup({ virtual_text = { enabled = false } })
  MiniTest.expect.equality(virtual_text.is_enabled(), false)
  virtual_text.toggle()
  MiniTest.expect.equality(virtual_text.is_enabled(), true)
end

T["get_virtual_text_lines()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["get_virtual_text_lines()"]["returns sorted list of lines with virtual text"] = function()
  local buf = create_test_buffer()

  virtual_text.add_virtual_text(buf, make_comment({ line = 7 }))
  virtual_text.add_virtual_text(buf, make_comment({ line = 2 }))
  virtual_text.add_virtual_text(buf, make_comment({ line = 5 }))

  local lines = virtual_text.get_virtual_text_lines(buf)
  MiniTest.expect.equality(lines, { 2, 5, 7 })
end

T["get_virtual_text_lines()"]["returns empty table for buffer without virtual text"] = function()
  local buf = create_test_buffer()
  local lines = virtual_text.get_virtual_text_lines(buf)
  MiniTest.expect.equality(#lines, 0)
end

T["update_comment()"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      get_config().setup({})
    end,
    post_case = function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end,
  },
})

T["update_comment()"]["updates virtual text for existing comment"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ line = 5, body = "Original" })

  virtual_text.add_virtual_text(buf, comment)
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)

  -- Update the comment body
  comment.body = "Updated"
  virtual_text.update_comment(buf, comment)

  -- Should still have exactly one extmark
  MiniTest.expect.equality(virtual_text.count_extmarks(buf), 1)
end

T["update_comment()"]["handles comment without line"] = function()
  local buf = create_test_buffer()
  local comment = make_comment({ no_line = true })

  -- Should not error
  virtual_text.update_comment(buf, comment)
end

T["get_namespace()"] = MiniTest.new_set()

T["get_namespace()"]["returns a valid namespace id"] = function()
  local ns = virtual_text.get_namespace()
  MiniTest.expect.equality(type(ns), "number")
  MiniTest.expect.equality(ns > 0, true)
end

return T
