-- Tests for review.ui.panel module
local T = MiniTest.new_set()

local panel = require("review.ui.panel")
local state = require("review.core.state")

-- Helper to reset state
local function reset_state()
  state.reset()
end

-- Helper to create a test PR
local function make_pr(opts)
  opts = opts or {}
  return {
    number = opts.number or 123,
    title = opts.title or "Test PR",
    description = opts.description or "Test description",
    author = opts.author or "testuser",
    branch = opts.branch or "feature-branch",
    base = opts.base or "main",
    created_at = opts.created_at or "2025-01-01T00:00:00Z",
    updated_at = opts.updated_at or "2025-01-01T00:00:00Z",
    additions = opts.additions or 10,
    deletions = opts.deletions or 5,
    changed_files = opts.changed_files or 2,
    state = opts.state or "open",
    url = opts.url or "https://github.com/test/repo/pull/123",
  }
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
    file = opts.file,
    line = opts.line,
    type = opts.type,
    resolved = opts.resolved,
    status = opts.status or "pending",
    replies = opts.replies,
    review_state = opts.review_state,
    github_id = opts.github_id,
    thread_id = opts.thread_id,
  }
end

-- Cleanup panel and floats after each test
local function cleanup()
  if state.state.panel_open then
    pcall(panel.close)
  end
  reset_state()
end

-- ============================================================================
-- get_namespace()
-- ============================================================================
T["get_namespace()"] = MiniTest.new_set()

T["get_namespace()"]["returns a valid namespace id"] = function()
  local ns = panel.get_namespace()
  MiniTest.expect.equality(type(ns), "number")
  MiniTest.expect.equality(ns > 0, true)
end

-- ============================================================================
-- is_open()
-- ============================================================================
T["is_open()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["is_open()"]["returns false when panel is closed"] = function()
  reset_state()
  MiniTest.expect.equality(panel.is_open(), false)
end

T["is_open()"]["returns true when panel is open"] = function()
  reset_state()
  state.state.panel_open = true
  MiniTest.expect.equality(panel.is_open(), true)
end

-- ============================================================================
-- render() - local mode
-- ============================================================================
T["render() local mode"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["render() local mode"]["renders header for local review"] = function()
  reset_state()
  state.state.mode = "local"
  state.state.base = "HEAD"
  state.state.files = {}

  local lines, _ = panel.render()
  MiniTest.expect.equality(lines[1], " Local Review ")
  MiniTest.expect.equality(type(lines), "table")
end

T["render() local mode"]["shows base ref and file count"] = function()
  reset_state()
  state.state.mode = "local"
  state.state.base = "main"
  state.state.files = { { path = "test.lua" }, { path = "test2.lua" } }

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("Base: main") and line:match("2 files") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() local mode"]["shows pending comments"] = function()
  reset_state()
  state.state.mode = "local"
  state.state.comments = {
    make_comment({ kind = "local", body = "My pending comment", status = "pending" }),
  }

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("My pending comment") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() local mode"]["shows no comments message when empty"] = function()
  reset_state()
  state.state.mode = "local"
  state.state.comments = {}

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("No comments yet") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() local mode"]["shows footer with AI action"] = function()
  reset_state()
  state.state.mode = "local"

  local lines, _ = panel.render()
  local last_line = lines[#lines]
  MiniTest.expect.equality(last_line:match("%[s%]end to AI") ~= nil, true)
end

-- ============================================================================
-- render() - PR mode
-- ============================================================================
T["render() PR mode"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["render() PR mode"]["renders PR header"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ number = 456, title = "Add new feature" })

  local lines, _ = panel.render()
  MiniTest.expect.equality(lines[1]:match("PR #456: Add new feature") ~= nil, true)
end

T["render() PR mode"]["shows author and base branch"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ author = "johndoe", base = "develop" })

  local lines, _ = panel.render()
  local found_author = false
  local found_base = false
  for _, line in ipairs(lines) do
    if line:match("@johndoe") then
      found_author = true
    end
    if line:match("develop") then
      found_base = true
    end
  end
  MiniTest.expect.equality(found_author, true)
  MiniTest.expect.equality(found_base, true)
end

T["render() PR mode"]["shows additions and deletions"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ additions = 100, deletions = 50 })

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("%+100") and line:match("%-50") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() PR mode"]["shows PR description"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ description = "This is a detailed description" })

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("This is a detailed description") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() PR mode"]["shows no description placeholder"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ description = "" })

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("%(no description%)") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() PR mode"]["shows DESCRIPTION section"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[DESCRIPTION%]") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() PR mode"]["shows conversation comments"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()
  state.state.comments = {
    make_comment({ kind = "conversation", body = "General comment", author = "reviewer" }),
  }

  local lines, _ = panel.render()
  local found_section = false
  local found_comment = false
  for _, line in ipairs(lines) do
    if line:match("%[CONVERSATION%]") then
      found_section = true
    end
    if line:match("General comment") then
      found_comment = true
    end
  end
  MiniTest.expect.equality(found_section, true)
  MiniTest.expect.equality(found_comment, true)
end

T["render() PR mode"]["shows code comments with location"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()
  state.state.comments = {
    make_comment({ kind = "review", body = "Fix this", file = "src/main.lua", line = 42 }),
  }

  local lines, _ = panel.render()
  local found_location = false
  local found_comment = false
  for _, line in ipairs(lines) do
    if line:match("src/main%.lua:42") then
      found_location = true
    end
    if line:match("Fix this") then
      found_comment = true
    end
  end
  MiniTest.expect.equality(found_location, true)
  MiniTest.expect.equality(found_comment, true)
end

T["render() PR mode"]["shows review_summary comments"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()
  state.state.comments = {
    make_comment({ kind = "review_summary", body = "LGTM", review_state = "APPROVED" }),
  }

  local lines, _ = panel.render()
  local found = false
  for _, line in ipairs(lines) do
    if line:match("LGTM") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render() PR mode"]["shows pending section for local comments"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()
  state.state.comments = {
    make_comment({ kind = "local", body = "My note", status = "pending" }),
  }

  local lines, _ = panel.render()
  local found_section = false
  local found_comment = false
  for _, line in ipairs(lines) do
    if line:match("%[MY PENDING%]") then
      found_section = true
    end
    if line:match("My note") then
      found_comment = true
    end
  end
  MiniTest.expect.equality(found_section, true)
  MiniTest.expect.equality(found_comment, true)
end

T["render() PR mode"]["shows actions footer"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()

  local lines, _ = panel.render()
  local last_line = lines[#lines]
  MiniTest.expect.equality(last_line:match("%[a%]pprove") ~= nil, true)
  MiniTest.expect.equality(last_line:match("%[g%]submit GitHub") ~= nil, true)
end

-- ============================================================================
-- render_comment()
-- ============================================================================
T["render_comment()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["render_comment()"]["renders author and time"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ author = "alice", created_at = "2025-01-01T00:00:00Z" })

  panel.render_comment(comment, lines, comment_map, false)

  local found_author = false
  for _, line in ipairs(lines) do
    if line:match("@alice") then
      found_author = true
      break
    end
  end
  MiniTest.expect.equality(found_author, true)
end

T["render_comment()"]["renders file location when show_location is true"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ file = "test.lua", line = 10 })

  panel.render_comment(comment, lines, comment_map, true)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("test%.lua:10") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["does not render location when show_location is false"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ file = "test.lua", line = 10 })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("test%.lua:10") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, false)
end

T["render_comment()"]["renders comment body"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ body = "This is my comment body" })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("This is my comment body") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["renders (no content) for empty body"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ body = "" })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%(no content%)") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["renders replies"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({
    body = "Original comment",
    replies = {
      { author = "bob", body = "Reply from bob" },
    },
  })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("@bob") and line:match("Reply from bob") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["shows edit/delete for local comments"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "local" })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[e%]dit") and line:match("%[d%]elete") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["shows reply/resolve for GitHub comments"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "review", resolved = false })

  panel.render_comment(comment, lines, comment_map, false)

  local found_reply = false
  local found_resolve = false
  for _, line in ipairs(lines) do
    if line:match("%[r%]eply") then
      found_reply = true
    end
    if line:match("%[R%]esolve") then
      found_resolve = true
    end
  end
  MiniTest.expect.equality(found_reply, true)
  MiniTest.expect.equality(found_resolve, true)
end

T["render_comment()"]["shows resolved status"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "review", resolved = true })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[resolved%]") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["shows unresolved status"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "review", resolved = false })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[unresolved%]") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["shows APPROVED badge"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "review_summary", review_state = "APPROVED" })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[APPROVED%]") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["shows CHANGES REQUESTED badge"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ kind = "review_summary", review_state = "CHANGES_REQUESTED" })

  panel.render_comment(comment, lines, comment_map, false)

  local found = false
  for _, line in ipairs(lines) do
    if line:match("%[CHANGES REQUESTED%]") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["render_comment()"]["populates comment_map with line mappings"] = function()
  reset_state()
  local lines = {}
  local comment_map = {}
  local comment = make_comment({ id = "unique_test_id" })

  panel.render_comment(comment, lines, comment_map, false)

  -- Should have mapped at least one line to the comment
  local found = false
  for _, c in pairs(comment_map) do
    if c.id == "unique_test_id" then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

-- ============================================================================
-- toggle()
-- ============================================================================
T["toggle()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["toggle()"]["opens panel when closed"] = function()
  reset_state()
  state.state.mode = "local"
  MiniTest.expect.equality(state.state.panel_open, false)

  panel.toggle()

  MiniTest.expect.equality(state.state.panel_open, true)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(state.state.layout.panel_win), true)
end

T["toggle()"]["closes panel when open"] = function()
  reset_state()
  state.state.mode = "local"
  panel.open()
  MiniTest.expect.equality(state.state.panel_open, true)

  panel.toggle()

  MiniTest.expect.equality(state.state.panel_open, false)
end

-- ============================================================================
-- open() / close()
-- ============================================================================
T["open() and close()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["open() and close()"]["open creates valid window and buffer"] = function()
  reset_state()
  state.state.mode = "local"

  panel.open()

  MiniTest.expect.equality(state.state.panel_open, true)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(state.state.layout.panel_win), true)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(state.state.layout.panel_buf), true)
end

T["open() and close()"]["open sets correct buffer options"] = function()
  reset_state()
  state.state.mode = "local"

  panel.open()

  local buf = state.state.layout.panel_buf
  MiniTest.expect.equality(vim.bo[buf].filetype, "review_panel")
  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")
  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
end

T["open() and close()"]["close cleans up window and state"] = function()
  reset_state()
  state.state.mode = "local"
  panel.open()
  local win = state.state.layout.panel_win

  panel.close()

  MiniTest.expect.equality(state.state.panel_open, false)
  MiniTest.expect.equality(state.state.layout.panel_win, nil)
  MiniTest.expect.equality(state.state.layout.panel_buf, nil)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(win), false)
end

T["open() and close()"]["close is safe to call when already closed"] = function()
  reset_state()
  -- Should not error
  panel.close()
  MiniTest.expect.equality(state.state.panel_open, false)
end

-- ============================================================================
-- refresh()
-- ============================================================================
T["refresh()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["refresh()"]["updates content when panel is open"] = function()
  reset_state()
  state.state.mode = "local"
  state.state.comments = {}
  panel.open()

  -- Add a comment and refresh
  state.state.comments = {
    make_comment({ kind = "local", body = "New comment after open", status = "pending" }),
  }
  panel.refresh()

  local buf = state.state.layout.panel_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found = false
  for _, line in ipairs(lines) do
    if line:match("New comment after open") then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["refresh()"]["does nothing when panel is closed"] = function()
  reset_state()
  -- Should not error
  panel.refresh()
end

-- ============================================================================
-- build_ai_prompt()
-- ============================================================================
T["build_ai_prompt()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["build_ai_prompt()"]["includes header"] = function()
  reset_state()
  local prompt = panel.build_ai_prompt()
  MiniTest.expect.equality(prompt:match("# Code Review") ~= nil, true)
end

T["build_ai_prompt()"]["includes PR info when available"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr({ number = 789, title = "My PR Title" })

  local prompt = panel.build_ai_prompt()
  MiniTest.expect.equality(prompt:match("PR #789") ~= nil, true)
  MiniTest.expect.equality(prompt:match("My PR Title") ~= nil, true)
end

T["build_ai_prompt()"]["includes pending comments"] = function()
  reset_state()
  state.state.comments = {
    make_comment({ kind = "local", body = "Fix the bug", status = "pending", file = "main.lua", line = 10 }),
  }

  local prompt = panel.build_ai_prompt()
  MiniTest.expect.equality(prompt:match("Fix the bug") ~= nil, true)
  MiniTest.expect.equality(prompt:match("main%.lua:10") ~= nil, true)
end

T["build_ai_prompt()"]["excludes submitted comments"] = function()
  reset_state()
  state.state.comments = {
    make_comment({ kind = "local", body = "Already submitted", status = "submitted" }),
    make_comment({ kind = "local", body = "Still pending", status = "pending" }),
  }

  local prompt = panel.build_ai_prompt()
  MiniTest.expect.equality(prompt:match("Already submitted") == nil, true)
  MiniTest.expect.equality(prompt:match("Still pending") ~= nil, true)
end

-- ============================================================================
-- get_comment_at_cursor()
-- ============================================================================
T["get_comment_at_cursor()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["get_comment_at_cursor()"]["returns nil when panel is closed"] = function()
  reset_state()
  local comment = panel.get_comment_at_cursor()
  MiniTest.expect.equality(comment, nil)
end

T["get_comment_at_cursor()"]["returns comment at cursor line"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()
  state.state.comments = {
    make_comment({ kind = "review", id = "test_comment_1", body = "First comment", file = "a.lua", line = 1 }),
  }

  panel.open()

  -- Move cursor to a line with the comment
  local buf = state.state.layout.panel_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local target_line = nil
  for i, line in ipairs(lines) do
    if line:match("First comment") then
      target_line = i
      break
    end
  end

  if target_line then
    vim.api.nvim_win_set_cursor(state.state.layout.panel_win, { target_line, 0 })
    local comment = panel.get_comment_at_cursor()
    MiniTest.expect.equality(comment ~= nil, true)
    MiniTest.expect.equality(comment.id, "test_comment_1")
  end
end

-- ============================================================================
-- apply_highlights()
-- ============================================================================
T["apply_highlights()"] = MiniTest.new_set({ hooks = { post_case = cleanup } })

T["apply_highlights()"]["applies extmarks to buffer"] = function()
  reset_state()
  state.state.mode = "pr"
  state.state.pr = make_pr()

  panel.open()

  local buf = state.state.layout.panel_buf
  local ns = panel.get_namespace()
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})

  -- Should have some extmarks
  MiniTest.expect.equality(#extmarks > 0, true)
end

return T
