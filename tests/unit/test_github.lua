-- Tests for review.integrations.github module
local T = MiniTest.new_set()

-- Use mock instead of real github module for testing
local mock_github = require("mocks.github")

-- Setup/teardown to install mock
T["setup"] = function()
  mock_github.reset()
end

T["mock basics"] = MiniTest.new_set()

T["mock basics"]["reset() clears state"] = function()
  mock_github.setup({ gh_available = false })
  mock_github.reset()
  local state = mock_github.get_state()
  MiniTest.expect.equality(state.gh_available, true)
  MiniTest.expect.equality(vim.tbl_count(state.prs), 0)
end

T["mock basics"]["setup() configures state"] = function()
  mock_github.reset()
  mock_github.setup({
    gh_available = false,
    open_prs = { { number = 1, title = "Test" } },
  })
  local state = mock_github.get_state()
  MiniTest.expect.equality(state.gh_available, false)
  MiniTest.expect.equality(#state.open_prs, 1)
end

T["mock basics"]["add_pr() adds PR to state"] = function()
  mock_github.reset()
  mock_github.add_pr({
    number = 42,
    title = "Test PR",
    author = "testuser",
    branch = "feature",
    base = "main",
  })
  local state = mock_github.get_state()
  MiniTest.expect.equality(state.prs[42] ~= nil, true)
  MiniTest.expect.equality(state.prs[42].title, "Test PR")
end

T["run()"] = MiniTest.new_set()

T["run()"]["returns error when gh not available"] = function()
  mock_github.reset()
  mock_github.setup({ gh_available = false })
  local result = mock_github.run({ "pr", "list" })
  MiniTest.expect.equality(result.code, 127)
  MiniTest.expect.equality(result.stderr:match("not found") ~= nil, true)
end

T["run()"]["handles pr diff command"] = function()
  mock_github.reset()
  mock_github.add_pr({ number = 123 })
  mock_github.set_pr_diff(123, "diff --git a/file.lua b/file.lua\n+added line")
  local result = mock_github.run({ "pr", "diff", "123" })
  MiniTest.expect.equality(result.code, 0)
  MiniTest.expect.equality(result.stdout:match("added line") ~= nil, true)
end

T["run()"]["handles pr diff for non-existent PR"] = function()
  mock_github.reset()
  local result = mock_github.run({ "pr", "diff", "999" })
  MiniTest.expect.equality(result.code, 1)
  MiniTest.expect.equality(result.stderr:match("no pull requests found") ~= nil, true)
end

T["run()"]["handles pr list command"] = function()
  mock_github.reset()
  mock_github.setup({
    open_prs = {
      { number = 1, title = "First PR", author = "user1", created_at = "2024-01-01" },
      { number = 2, title = "Second PR", author = "user2", created_at = "2024-01-02" },
    },
  })
  local result = mock_github.run({ "pr", "list", "--json", "number,title", "--state", "open" })
  MiniTest.expect.equality(result.code, 0)
  local data = vim.json.decode(result.stdout)
  MiniTest.expect.equality(#data, 2)
end

T["run()"]["handles pr list for review requests"] = function()
  mock_github.reset()
  mock_github.setup({
    review_requests = {
      { number = 10, title = "Review me", author = "colleague", created_at = "2024-01-01" },
    },
  })
  local result = mock_github.run({ "pr", "list", "--search", "review-requested:@me" })
  MiniTest.expect.equality(result.code, 0)
  local data = vim.json.decode(result.stdout)
  MiniTest.expect.equality(#data, 1)
  MiniTest.expect.equality(data[1].number, 10)
end

T["run()"]["handles pr view command"] = function()
  mock_github.reset()
  mock_github.add_pr({
    number = 42,
    title = "Test PR",
    description = "PR description",
    author = "testuser",
    branch = "feature",
    base = "main",
    created_at = "2024-01-01",
    updated_at = "2024-01-02",
    additions = 10,
    deletions = 5,
    changed_files = 2,
    state = "open",
    url = "https://github.com/owner/repo/pull/42",
  })
  local result = mock_github.run({ "pr", "view", "42", "--json", "number,title" })
  MiniTest.expect.equality(result.code, 0)
  local data = vim.json.decode(result.stdout)
  MiniTest.expect.equality(data.number, 42)
  MiniTest.expect.equality(data.title, "Test PR")
end

T["run()"]["handles pr review command"] = function()
  mock_github.reset()
  local result = mock_github.run({ "pr", "review", "42", "--approve", "--body", "LGTM" })
  MiniTest.expect.equality(result.code, 0)
  local reviews = mock_github.get_submitted_reviews()
  MiniTest.expect.equality(#reviews, 1)
  MiniTest.expect.equality(reviews[1].event, "APPROVE")
  MiniTest.expect.equality(reviews[1].body, "LGTM")
end

T["api()"] = MiniTest.new_set()

T["api()"]["fetches PR data"] = function()
  mock_github.reset()
  mock_github.add_pr({
    number = 42,
    title = "Test PR",
    description = "Description",
    author = "testuser",
    branch = "feature",
    base = "main",
  })
  local data = mock_github.api("repos/owner/repo/pulls/42")
  MiniTest.expect.equality(data ~= nil, true)
  MiniTest.expect.equality(data.number, 42)
end

T["api()"]["returns nil for non-existent PR"] = function()
  mock_github.reset()
  local data = mock_github.api("repos/owner/repo/pulls/999")
  MiniTest.expect.equality(data, nil)
end

T["api()"]["handles custom responses"] = function()
  mock_github.reset()
  mock_github.setup({
    api_responses = {
      ["custom/endpoint"] = { custom = "data" },
    },
  })
  local data = mock_github.api("custom/endpoint")
  MiniTest.expect.equality(data.custom, "data")
end

T["fetch_pr()"] = MiniTest.new_set()

T["fetch_pr()"]["returns PR data"] = function()
  mock_github.reset()
  mock_github.add_pr({
    number = 42,
    title = "Test PR",
    author = "testuser",
    branch = "feature",
    base = "main",
  })
  local pr = mock_github.fetch_pr(42)
  MiniTest.expect.equality(pr ~= nil, true)
  MiniTest.expect.equality(pr.number, 42)
  MiniTest.expect.equality(pr.title, "Test PR")
end

T["fetch_pr()"]["returns nil for non-existent PR"] = function()
  mock_github.reset()
  local pr = mock_github.fetch_pr(999)
  MiniTest.expect.equality(pr, nil)
end

T["fetch_pr_diff()"] = MiniTest.new_set()

T["fetch_pr_diff()"]["returns diff content"] = function()
  mock_github.reset()
  mock_github.add_pr({ number = 42 })
  mock_github.set_pr_diff(42, "diff content here")
  local diff = mock_github.fetch_pr_diff(42)
  MiniTest.expect.equality(diff, "diff content here")
end

T["fetch_pr_diff()"]["returns empty for non-existent PR"] = function()
  mock_github.reset()
  local diff = mock_github.fetch_pr_diff(999)
  MiniTest.expect.equality(diff, "")
end

T["fetch_conversation_comments()"] = MiniTest.new_set()

T["fetch_conversation_comments()"]["returns conversation comments"] = function()
  mock_github.reset()
  mock_github.add_comments(42, {
    {
      id = "gh_conv_1",
      kind = "conversation",
      body = "First comment",
      author = "user1",
      created_at = "2024-01-01",
      github_id = 1,
    },
    {
      id = "gh_conv_2",
      kind = "conversation",
      body = "Second comment",
      author = "user2",
      created_at = "2024-01-02",
      github_id = 2,
    },
  }, "conversation")
  local comments = mock_github.fetch_conversation_comments(42)
  MiniTest.expect.equality(#comments, 2)
  MiniTest.expect.equality(comments[1].body, "First comment")
end

T["fetch_conversation_comments()"]["returns empty for no comments"] = function()
  mock_github.reset()
  local comments = mock_github.fetch_conversation_comments(999)
  MiniTest.expect.equality(#comments, 0)
end

T["fetch_review_comments()"] = MiniTest.new_set()

T["fetch_review_comments()"]["returns code comments"] = function()
  mock_github.reset()
  mock_github.add_comments(42, {
    {
      id = "gh_review_1",
      kind = "review",
      body = "Code review comment",
      author = "reviewer",
      created_at = "2024-01-01",
      file = "src/main.lua",
      line = 10,
      github_id = 1,
    },
  }, "review")
  local comments = mock_github.fetch_review_comments(42)
  MiniTest.expect.equality(#comments, 1)
  MiniTest.expect.equality(comments[1].file, "src/main.lua")
  MiniTest.expect.equality(comments[1].line, 10)
end

T["fetch_reviews()"] = MiniTest.new_set()

T["fetch_reviews()"]["returns review summaries"] = function()
  mock_github.reset()
  mock_github.add_comments(42, {
    {
      id = "gh_summary_1",
      kind = "review_summary",
      body = "LGTM!",
      author = "approver",
      created_at = "2024-01-01",
      review_state = "APPROVED",
      github_id = 1,
    },
  }, "review_summary")
  local reviews = mock_github.fetch_reviews(42)
  MiniTest.expect.equality(#reviews, 1)
  MiniTest.expect.equality(reviews[1].body, "LGTM!")
  MiniTest.expect.equality(reviews[1].review_state, "APPROVED")
end

T["group_into_threads()"] = MiniTest.new_set()

T["group_into_threads()"]["groups replies under parent"] = function()
  mock_github.reset()
  local comments = {
    {
      id = "gh_review_1",
      body = "Parent comment",
      author = "user1",
      github_id = 1,
    },
    {
      id = "gh_review_2",
      body = "Reply 1",
      author = "user2",
      github_id = 2,
      in_reply_to_id = 1,
    },
    {
      id = "gh_review_3",
      body = "Reply 2",
      author = "user3",
      github_id = 3,
      in_reply_to_id = 1,
    },
  }
  local threads = mock_github.group_into_threads(comments)
  MiniTest.expect.equality(#threads, 1)
  MiniTest.expect.equality(threads[1].body, "Parent comment")
  MiniTest.expect.equality(#threads[1].replies, 2)
end

T["group_into_threads()"]["handles multiple threads"] = function()
  mock_github.reset()
  local comments = {
    {
      id = "gh_review_1",
      body = "Thread 1",
      github_id = 1,
    },
    {
      id = "gh_review_2",
      body = "Thread 2",
      github_id = 2,
    },
    {
      id = "gh_review_3",
      body = "Reply to thread 1",
      github_id = 3,
      in_reply_to_id = 1,
    },
  }
  local threads = mock_github.group_into_threads(comments)
  MiniTest.expect.equality(#threads, 2)
end

T["group_into_threads()"]["handles comments with no parent"] = function()
  mock_github.reset()
  local comments = {
    {
      id = "gh_review_1",
      body = "Orphan reply",
      github_id = 2,
      in_reply_to_id = 999, -- Non-existent parent
    },
  }
  local threads = mock_github.group_into_threads(comments)
  -- Orphan replies don't create threads
  MiniTest.expect.equality(#threads, 0)
end

T["fetch_review_requests()"] = MiniTest.new_set()

T["fetch_review_requests()"]["returns review request PRs"] = function()
  mock_github.reset()
  mock_github.setup({
    review_requests = {
      { number = 10, title = "Review this", author = "colleague" },
      { number = 20, title = "Also review", author = "teammate" },
    },
  })
  local prs = mock_github.fetch_review_requests()
  MiniTest.expect.equality(#prs, 2)
  MiniTest.expect.equality(prs[1].number, 10)
end

T["fetch_review_requests()"]["returns empty when none"] = function()
  mock_github.reset()
  local prs = mock_github.fetch_review_requests()
  MiniTest.expect.equality(#prs, 0)
end

T["fetch_open_prs()"] = MiniTest.new_set()

T["fetch_open_prs()"]["returns open PRs"] = function()
  mock_github.reset()
  mock_github.setup({
    open_prs = {
      { number = 1, title = "Open PR 1", author = "user1" },
      { number = 2, title = "Open PR 2", author = "user2" },
      { number = 3, title = "Open PR 3", author = "user3" },
    },
  })
  local prs = mock_github.fetch_open_prs()
  MiniTest.expect.equality(#prs, 3)
end

T["submit_review()"] = MiniTest.new_set()

T["submit_review()"]["records APPROVE event"] = function()
  mock_github.reset()
  mock_github.approve()
  local reviews = mock_github.get_submitted_reviews()
  MiniTest.expect.equality(#reviews, 1)
  MiniTest.expect.equality(reviews[1].event, "APPROVE")
end

T["submit_review()"]["records REQUEST_CHANGES event"] = function()
  mock_github.reset()
  mock_github.request_changes()
  local reviews = mock_github.get_submitted_reviews()
  MiniTest.expect.equality(#reviews, 1)
  MiniTest.expect.equality(reviews[1].event, "REQUEST_CHANGES")
end

T["install/restore"] = MiniTest.new_set()

T["install/restore"]["install replaces module in package.loaded"] = function()
  mock_github.reset()
  mock_github.install()
  local github = require("review.integrations.github")
  -- Should be the mock
  MiniTest.expect.equality(github.reset ~= nil, true)
  mock_github.restore()
end

T["install/restore"]["restore brings back original"] = function()
  mock_github.reset()
  mock_github.install()
  mock_github.restore()
  -- After restore, the module should be nil or original
  local restored = package.loaded["review.integrations.github"]
  -- Either nil or the original (depends on if it was loaded before)
  MiniTest.expect.equality(restored == nil or restored.reset == nil, true)
end

-- Test the real github module interface (without actual API calls)
T["real module"] = MiniTest.new_set()

T["real module"]["exports expected functions"] = function()
  -- Force reload after restore
  package.loaded["review.integrations.github"] = nil
  local github = require("review.integrations.github")

  MiniTest.expect.equality(type(github.run), "function")
  MiniTest.expect.equality(type(github.run_async), "function")
  MiniTest.expect.equality(type(github.is_available), "function")
  MiniTest.expect.equality(type(github.api), "function")
  MiniTest.expect.equality(type(github.graphql), "function")
  MiniTest.expect.equality(type(github.fetch_pr), "function")
  MiniTest.expect.equality(type(github.fetch_pr_diff), "function")
  MiniTest.expect.equality(type(github.fetch_conversation_comments), "function")
  MiniTest.expect.equality(type(github.fetch_review_comments), "function")
  MiniTest.expect.equality(type(github.fetch_reviews), "function")
  MiniTest.expect.equality(type(github.fetch_all_comments), "function")
  MiniTest.expect.equality(type(github.group_into_threads), "function")
  MiniTest.expect.equality(type(github.fetch_review_requests), "function")
  MiniTest.expect.equality(type(github.fetch_open_prs), "function")
  MiniTest.expect.equality(type(github.add_conversation_comment), "function")
  MiniTest.expect.equality(type(github.submit_review), "function")
  MiniTest.expect.equality(type(github.approve), "function")
  MiniTest.expect.equality(type(github.request_changes), "function")
  MiniTest.expect.equality(type(github.reply_to_comment), "function")
  MiniTest.expect.equality(type(github.reply_to_comment_prompt), "function")
  MiniTest.expect.equality(type(github.resolve_thread), "function")
  MiniTest.expect.equality(type(github.toggle_thread_resolved), "function")
  MiniTest.expect.equality(type(github.refresh_comments), "function")
  MiniTest.expect.equality(type(github.update_file_comment_counts), "function")
  MiniTest.expect.equality(type(github.create_code_comment), "function")
  MiniTest.expect.equality(type(github.checkout_pr), "function")
  MiniTest.expect.equality(type(github.get_current_pr_number), "function")
  MiniTest.expect.equality(type(github.open_in_browser), "function")
end

T["real module"]["group_into_threads sorts by file and line"] = function()
  package.loaded["review.integrations.github"] = nil
  local github = require("review.integrations.github")

  local comments = {
    { id = "1", file = "src/b.lua", line = 20, github_id = 1 },
    { id = "2", file = "src/a.lua", line = 10, github_id = 2 },
    { id = "3", file = "src/a.lua", line = 5, github_id = 3 },
  }

  local threads = github.group_into_threads(comments)
  MiniTest.expect.equality(#threads, 3)
  MiniTest.expect.equality(threads[1].file, "src/a.lua")
  MiniTest.expect.equality(threads[1].line, 5)
  MiniTest.expect.equality(threads[2].file, "src/a.lua")
  MiniTest.expect.equality(threads[2].line, 10)
  MiniTest.expect.equality(threads[3].file, "src/b.lua")
  MiniTest.expect.equality(threads[3].line, 20)
end

T["real module"]["group_into_threads handles replies correctly"] = function()
  package.loaded["review.integrations.github"] = nil
  local github = require("review.integrations.github")

  local comments = {
    { id = "1", body = "Parent", github_id = 100, file = "test.lua", line = 1 },
    { id = "2", body = "Reply 1", github_id = 101, in_reply_to_id = 100, created_at = "2024-01-01" },
    { id = "3", body = "Reply 2", github_id = 102, in_reply_to_id = 100, created_at = "2024-01-02" },
  }

  local threads = github.group_into_threads(comments)
  MiniTest.expect.equality(#threads, 1)
  MiniTest.expect.equality(threads[1].body, "Parent")
  MiniTest.expect.equality(#threads[1].replies, 2)
  -- Replies should be sorted by created_at
  MiniTest.expect.equality(threads[1].replies[1].body, "Reply 1")
  MiniTest.expect.equality(threads[1].replies[2].body, "Reply 2")
end

return T
