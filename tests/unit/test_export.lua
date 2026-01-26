-- Tests for review.export module
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Reset modules
      package.loaded["review.export"] = nil
      package.loaded["review.core.state"] = nil
    end,
    post_case = function()
      -- Reset state
      local state = require("review.core.state")
      state.reset()
    end,
  },
})

local function get_export()
  return require("review.export")
end

local function get_state()
  return require("review.core.state")
end

-- Setup state with mock data
local function setup_local_review()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.base = "main"
  state.state.comments = {
    {
      id = "c1",
      kind = "local",
      body = "This needs error handling",
      file = "src/utils.lua",
      line = 42,
      type = "issue",
      status = "pending",
    },
    {
      id = "c2",
      kind = "local",
      body = "Consider using a constant here",
      file = "src/utils.lua",
      line = 55,
      type = "suggestion",
      status = "pending",
    },
    {
      id = "c3",
      kind = "local",
      body = "Great refactoring!",
      file = "src/config.lua",
      line = 10,
      type = "praise",
      status = "pending",
    },
  }
  state.state.files = {
    { path = "src/utils.lua", status = "M" },
    { path = "src/config.lua", status = "A" },
  }
end

local function setup_pr_review()
  local state = get_state()
  state.reset()
  state.set_mode("pr")
  state.state.pr = {
    number = 142,
    title = "Add theme support",
    description = "This PR adds theme support to the application",
    author = "testuser",
    branch = "feature/themes",
    base = "main",
    additions = 142,
    deletions = 38,
    changed_files = 3,
  }
  state.state.comments = {
    {
      id = "gh_1",
      kind = "review",
      body = "Existing GitHub comment",
      author = "reviewer",
      file = "src/theme.lua",
      line = 15,
    },
    {
      id = "local_1",
      kind = "local",
      body = "Missing null check",
      file = "src/theme.lua",
      line = 25,
      type = "issue",
      status = "pending",
    },
  }
end

T["generate_markdown()"] = MiniTest.new_set()

T["generate_markdown()"]["includes header for local review"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("# Code Review") ~= nil, true)
end

T["generate_markdown()"]["includes PR info for PR review"] = function()
  setup_pr_review()
  local export = get_export()

  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("# PR #142") ~= nil, true)
  MiniTest.expect.equality(md:find("Add theme support") ~= nil, true)
  MiniTest.expect.equality(md:find("@testuser") ~= nil, true)
  MiniTest.expect.equality(md:find("feature/themes") ~= nil, true)
end

T["generate_markdown()"]["includes comments section"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("## Review Comments") ~= nil, true)
  MiniTest.expect.equality(md:find("This needs error handling") ~= nil, true)
  MiniTest.expect.equality(md:find("src/utils.lua:42") ~= nil, true)
end

T["generate_markdown()"]["formats comment types correctly"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("%[ISSUE%]") ~= nil, true)
  MiniTest.expect.equality(md:find("%[SUGGESTION%]") ~= nil, true)
  MiniTest.expect.equality(md:find("%[PRAISE%]") ~= nil, true)
end

T["generate_markdown()"]["sorts comments by file and line"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown()

  -- src/config.lua should come before src/utils.lua alphabetically
  local config_pos = md:find("src/config.lua")
  local utils_pos = md:find("src/utils.lua")
  MiniTest.expect.equality(config_pos < utils_pos, true)
end

T["generate_markdown()"]["includes instructions when enabled"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown({ include_instructions = true })

  MiniTest.expect.equality(md:find("I reviewed your code") ~= nil, true)
  MiniTest.expect.equality(md:find("Comment types:") ~= nil, true)
end

T["generate_markdown()"]["excludes instructions when disabled"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown({ include_instructions = false })

  MiniTest.expect.equality(md:find("I reviewed your code"), nil)
end

T["generate_markdown()"]["excludes PR info when disabled"] = function()
  setup_pr_review()
  local export = get_export()

  local md = export.generate_markdown({ include_pr_info = false })

  MiniTest.expect.equality(md:find("@testuser"), nil)
  MiniTest.expect.equality(md:find("feature/themes"), nil)
end

T["generate_markdown()"]["filters by only_pending"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {
    { id = "c1", kind = "local", body = "Pending", status = "pending", file = "a.lua", line = 1 },
    { id = "c2", kind = "local", body = "Submitted", status = "submitted", file = "a.lua", line = 2 },
  }

  local export = get_export()
  local md = export.generate_markdown({ only_pending = true })

  MiniTest.expect.equality(md:find("Pending") ~= nil, true)
  MiniTest.expect.equality(md:find("Submitted"), nil)
end

T["generate_markdown()"]["filters by comment_types"] = function()
  setup_local_review()
  local export = get_export()

  local md = export.generate_markdown({ comment_types = { "issue" } })

  MiniTest.expect.equality(md:find("error handling") ~= nil, true)
  MiniTest.expect.equality(md:find("Consider using"), nil)
  MiniTest.expect.equality(md:find("Great refactoring"), nil)
end

T["generate_markdown()"]["shows no comments message when empty"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {}

  local export = get_export()
  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("No comments yet") ~= nil, true)
end

T["generate_plain()"] = MiniTest.new_set()

T["generate_plain()"]["returns plain text format"] = function()
  setup_local_review()
  local export = get_export()

  local plain = export.generate_plain()

  -- Should have numbered list without markdown
  MiniTest.expect.equality(plain:find("1%.") ~= nil, true)
  MiniTest.expect.equality(plain:find("%[ISSUE%]") ~= nil, true)
  MiniTest.expect.equality(plain:find("error handling") ~= nil, true)
end

T["generate_plain()"]["filters by only_pending"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {
    { id = "c1", kind = "local", body = "Pending", status = "pending", file = "a.lua", line = 1 },
    { id = "c2", kind = "local", body = "Submitted", status = "submitted", file = "a.lua", line = 2 },
  }

  local export = get_export()
  local plain = export.generate_plain({ only_pending = true })

  MiniTest.expect.equality(plain:find("Pending") ~= nil, true)
  MiniTest.expect.equality(plain:find("Submitted"), nil)
end

T["generate_json()"] = MiniTest.new_set()

T["generate_json()"]["returns valid JSON"] = function()
  setup_local_review()
  local export = get_export()

  local json_str = export.generate_json()
  local ok, data = pcall(vim.json.decode, json_str)

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(type(data), "table")
end

T["generate_json()"]["includes mode and comments"] = function()
  setup_local_review()
  local export = get_export()

  local json_str = export.generate_json()
  local data = vim.json.decode(json_str)

  MiniTest.expect.equality(data.mode, "local")
  MiniTest.expect.equality(type(data.comments), "table")
  MiniTest.expect.equality(#data.comments, 3)
end

T["generate_json()"]["includes exported_at timestamp"] = function()
  setup_local_review()
  local export = get_export()

  local json_str = export.generate_json()
  local data = vim.json.decode(json_str)

  MiniTest.expect.equality(type(data.exported_at), "string")
  MiniTest.expect.equality(data.exported_at:find("T") ~= nil, true) -- ISO format
end

T["generate_json()"]["includes PR data for PR mode"] = function()
  setup_pr_review()
  local export = get_export()

  local json_str = export.generate_json()
  local data = vim.json.decode(json_str)

  MiniTest.expect.equality(data.mode, "pr")
  MiniTest.expect.equality(data.pr.number, 142)
  MiniTest.expect.equality(data.pr.title, "Add theme support")
end

T["generate_json()"]["filters by only_pending"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {
    { id = "c1", kind = "local", body = "Pending", status = "pending" },
    { id = "c2", kind = "local", body = "Submitted", status = "submitted" },
  }

  local export = get_export()
  local json_str = export.generate_json({ only_pending = true })
  local data = vim.json.decode(json_str)

  MiniTest.expect.equality(#data.comments, 1)
  MiniTest.expect.equality(data.comments[1].body, "Pending")
end

T["generate()"] = MiniTest.new_set()

T["generate()"]["defaults to markdown format"] = function()
  setup_local_review()
  local export = get_export()

  local output = export.generate()

  MiniTest.expect.equality(output:find("# Code Review") ~= nil, true)
end

T["generate()"]["respects format option"] = function()
  setup_local_review()
  local export = get_export()

  local json = export.generate({ format = "json" })
  local ok = pcall(vim.json.decode, json)
  MiniTest.expect.equality(ok, true)

  local plain = export.generate({ format = "plain" })
  MiniTest.expect.equality(plain:find("1%.") ~= nil, true)
  MiniTest.expect.equality(plain:find("# Code Review"), nil)
end

T["get_comment_summary()"] = MiniTest.new_set()

T["get_comment_summary()"]["counts comment types correctly"] = function()
  setup_local_review()
  local export = get_export()

  local summary = export.get_comment_summary()

  MiniTest.expect.equality(summary.issue, 1)
  MiniTest.expect.equality(summary.suggestion, 1)
  MiniTest.expect.equality(summary.praise, 1)
  MiniTest.expect.equality(summary.total, 3)
end

T["get_comment_summary()"]["returns zeros for empty state"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {}

  local export = get_export()
  local summary = export.get_comment_summary()

  MiniTest.expect.equality(summary.issue, 0)
  MiniTest.expect.equality(summary.suggestion, 0)
  MiniTest.expect.equality(summary.total, 0)
end

T["get_comment_summary()"]["only counts local comments"] = function()
  setup_pr_review() -- Has 1 github comment and 1 local comment
  local export = get_export()

  local summary = export.get_comment_summary()

  MiniTest.expect.equality(summary.total, 1) -- Only local comment
end

T["to_clipboard()"] = MiniTest.new_set()

T["to_clipboard()"]["copies to clipboard registers"] = function()
  setup_local_review()
  local export = get_export()

  -- Clear registers first
  vim.fn.setreg("+", "")
  vim.fn.setreg("*", "")

  export.to_clipboard()

  local content = vim.fn.getreg("+")
  MiniTest.expect.equality(content:find("Code Review") ~= nil, true)
  MiniTest.expect.equality(content:find("error handling") ~= nil, true)
end

T["edge cases"] = MiniTest.new_set()

T["edge cases"]["handles comments without file"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {
    { id = "c1", kind = "local", body = "General comment", type = "note" },
  }

  local export = get_export()
  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("General comment") ~= nil, true)
  MiniTest.expect.equality(md:find("%[NOTE%]") ~= nil, true)
end

T["edge cases"]["handles comments without type"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("local")
  state.state.comments = {
    { id = "c1", kind = "local", body = "No type comment", file = "a.lua", line = 1 },
  }

  local export = get_export()
  local md = export.generate_markdown()

  -- Should default to NOTE
  MiniTest.expect.equality(md:find("%[NOTE%]") ~= nil, true)
end

T["edge cases"]["handles PR without description"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("pr")
  state.state.pr = {
    number = 1,
    title = "Test PR",
    author = "user",
    branch = "feature",
    base = "main",
    additions = 10,
    deletions = 5,
    changed_files = 1,
  }
  state.state.comments = {}

  local export = get_export()
  local md = export.generate_markdown()

  -- Should not have description section
  MiniTest.expect.equality(md:find("## Description"), nil)
end

T["edge cases"]["handles PR with description"] = function()
  local state = get_state()
  state.reset()
  state.set_mode("pr")
  state.state.pr = {
    number = 1,
    title = "Test PR",
    description = "This is a detailed description",
    author = "user",
    branch = "feature",
    base = "main",
    additions = 10,
    deletions = 5,
    changed_files = 1,
  }
  state.state.comments = {}

  local export = get_export()
  local md = export.generate_markdown()

  MiniTest.expect.equality(md:find("## Description") ~= nil, true)
  MiniTest.expect.equality(md:find("detailed description") ~= nil, true)
end

return T
