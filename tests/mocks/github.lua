-- Mock for GitHub integration (gh CLI wrapper)
-- Allows testing PR review workflow without actual GitHub API calls
local M = {}

---@class MockGithub.State
---@field prs table<number, Review.PR> PR number -> PR data
---@field pr_diffs table<number, string> PR number -> diff output
---@field conversation_comments table<number, Review.Comment[]> PR number -> comments
---@field review_comments table<number, Review.Comment[]> PR number -> code comments
---@field reviews table<number, Review.Comment[]> PR number -> review summaries
---@field review_requests Review.PR[] PRs where user is requested reviewer
---@field open_prs Review.PR[] All open PRs
---@field gh_available boolean Is gh CLI available
---@field api_responses table<string, any> Custom API responses by endpoint
---@field submitted_reviews table Submitted reviews for verification

---@type MockGithub.State
local state = {
  prs = {},
  pr_diffs = {},
  conversation_comments = {},
  review_comments = {},
  reviews = {},
  review_requests = {},
  open_prs = {},
  gh_available = true,
  api_responses = {},
  submitted_reviews = {},
}

-- Store original module for restore
local original_github = nil

---Reset mock state to defaults
function M.reset()
  state = {
    prs = {},
    pr_diffs = {},
    conversation_comments = {},
    review_comments = {},
    reviews = {},
    review_requests = {},
    open_prs = {},
    gh_available = true,
    api_responses = {},
    submitted_reviews = {},
  }
end

---Configure mock state
---@param opts table Partial state to merge
function M.setup(opts)
  if not opts then
    return
  end
  for k, v in pairs(opts) do
    if v == vim.NIL then
      state[k] = nil
    else
      state[k] = v
    end
  end
end

---Get current mock state (for assertions)
---@return MockGithub.State
function M.get_state()
  return vim.deepcopy(state)
end

---Add a PR to the mock
---@param pr Review.PR
function M.add_pr(pr)
  state.prs[pr.number] = pr
  state.pr_diffs[pr.number] = state.pr_diffs[pr.number] or ""
  state.conversation_comments[pr.number] = state.conversation_comments[pr.number] or {}
  state.review_comments[pr.number] = state.review_comments[pr.number] or {}
  state.reviews[pr.number] = state.reviews[pr.number] or {}
end

---Add comments for a PR
---@param pr_number number
---@param comments Review.Comment[]
---@param kind "conversation" | "review" | "review_summary"
function M.add_comments(pr_number, comments, kind)
  if kind == "conversation" then
    state.conversation_comments[pr_number] = comments
  elseif kind == "review" then
    state.review_comments[pr_number] = comments
  elseif kind == "review_summary" then
    state.reviews[pr_number] = comments
  end
end

---Set PR diff
---@param pr_number number
---@param diff string
function M.set_pr_diff(pr_number, diff)
  state.pr_diffs[pr_number] = diff
end

-- Mock implementations matching github.lua interface

---Run gh CLI command
---@param args string[]
---@return {stdout: string, stderr: string, code: number}
function M.run(args)
  if not state.gh_available then
    return { stdout = "", stderr = "gh: command not found", code = 127 }
  end

  local result = { stdout = "", stderr = "", code = 0 }
  local cmd = args[1]

  if cmd == "pr" then
    local subcmd = args[2]
    if subcmd == "diff" then
      local pr_num = tonumber(args[3])
      if pr_num and state.pr_diffs[pr_num] then
        result.stdout = state.pr_diffs[pr_num]
      else
        result.code = 1
        result.stderr = "no pull requests found"
      end
    elseif subcmd == "list" then
      -- Check if looking for review requests
      local is_review_request = false
      for _, arg in ipairs(args) do
        if arg:match("review%-requested") then
          is_review_request = true
          break
        end
      end

      local prs = is_review_request and state.review_requests or state.open_prs
      local items = {}
      for _, pr in ipairs(prs) do
        table.insert(items, {
          number = pr.number,
          title = pr.title,
          author = { login = pr.author },
          createdAt = pr.created_at,
        })
      end
      result.stdout = vim.json.encode(items)
    elseif subcmd == "view" then
      local pr_num = tonumber(args[3])
      if pr_num and state.prs[pr_num] then
        local pr = state.prs[pr_num]
        result.stdout = vim.json.encode({
          number = pr.number,
          title = pr.title,
          body = pr.description,
          author = { login = pr.author },
          headRefName = pr.branch,
          baseRefName = pr.base,
          createdAt = pr.created_at,
          updatedAt = pr.updated_at,
          additions = pr.additions,
          deletions = pr.deletions,
          changedFiles = pr.changed_files,
          state = pr.state,
          url = pr.url,
        })
      else
        result.code = 1
        result.stderr = "no pull requests found"
      end
    elseif subcmd == "review" then
      -- Store submitted review for verification
      local pr_num = tonumber(args[3])
      local review = { pr_number = pr_num, args = args }
      for i, arg in ipairs(args) do
        if arg == "--approve" then
          review.event = "APPROVE"
        elseif arg == "--request-changes" then
          review.event = "REQUEST_CHANGES"
        elseif arg == "--comment" then
          review.event = "COMMENT"
        elseif arg == "--body" then
          review.body = args[i + 1]
        end
      end
      table.insert(state.submitted_reviews, review)
      result.stdout = ""
    end
  elseif cmd == "api" then
    local endpoint = args[2]

    -- Check for custom response
    if state.api_responses[endpoint] then
      result.stdout = vim.json.encode(state.api_responses[endpoint])
      return result
    end

    -- Parse endpoint for PR-related APIs
    local owner, repo, pr_num = endpoint:match("repos/([^/]+)/([^/]+)/pulls/(%d+)$")
    if pr_num then
      pr_num = tonumber(pr_num)
      if state.prs[pr_num] then
        local pr = state.prs[pr_num]
        result.stdout = vim.json.encode({
          number = pr.number,
          title = pr.title,
          body = pr.description,
          user = { login = pr.author },
          head = { ref = pr.branch },
          base = { ref = pr.base },
          created_at = pr.created_at,
          updated_at = pr.updated_at,
          additions = pr.additions,
          deletions = pr.deletions,
          changed_files = pr.changed_files,
          state = pr.state,
          html_url = pr.url,
        })
      else
        result.code = 1
        result.stderr = "Not Found"
      end
      return result
    end

    -- Conversation comments
    owner, repo, pr_num = endpoint:match("repos/([^/]+)/([^/]+)/issues/(%d+)/comments")
    if pr_num then
      pr_num = tonumber(pr_num)
      local comments = state.conversation_comments[pr_num] or {}
      local items = {}
      for _, c in ipairs(comments) do
        table.insert(items, {
          id = c.github_id or tonumber(c.id:match("%d+")) or 1,
          body = c.body,
          user = { login = c.author },
          created_at = c.created_at,
          updated_at = c.updated_at,
        })
      end
      result.stdout = vim.json.encode(items)
      return result
    end

    -- Review comments
    owner, repo, pr_num = endpoint:match("repos/([^/]+)/([^/]+)/pulls/(%d+)/comments")
    if pr_num then
      pr_num = tonumber(pr_num)
      local comments = state.review_comments[pr_num] or {}
      local items = {}
      for _, c in ipairs(comments) do
        table.insert(items, {
          id = c.github_id or tonumber(c.id:match("%d+")) or 1,
          body = c.body,
          user = { login = c.author },
          created_at = c.created_at,
          updated_at = c.updated_at,
          path = c.file,
          line = c.line,
          original_line = c.line,
          side = c.side or "RIGHT",
          commit_id = c.commit_id,
          in_reply_to_id = c.in_reply_to_id,
        })
      end
      result.stdout = vim.json.encode(items)
      return result
    end

    -- Reviews (summaries)
    owner, repo, pr_num = endpoint:match("repos/([^/]+)/([^/]+)/pulls/(%d+)/reviews")
    if pr_num then
      pr_num = tonumber(pr_num)
      local reviews = state.reviews[pr_num] or {}
      local items = {}
      for _, r in ipairs(reviews) do
        table.insert(items, {
          id = r.github_id or tonumber(r.id:match("%d+")) or 1,
          body = r.body,
          user = { login = r.author },
          submitted_at = r.created_at,
          state = r.review_state,
        })
      end
      result.stdout = vim.json.encode(items)
      return result
    end

    -- GraphQL endpoint
    if endpoint == "graphql" then
      -- Handle thread resolution mutations
      result.stdout = vim.json.encode({ data = { thread = { isResolved = true } } })
      return result
    end

    -- Unknown endpoint
    result.stdout = "[]"
  end

  return result
end

---Run gh api command
---@param endpoint string
---@param opts? {method?: string, fields?: table}
---@return table?
function M.api(endpoint, opts)
  opts = opts or {}
  local args = { "api", endpoint }

  if opts.method then
    table.insert(args, "--method")
    table.insert(args, opts.method)
  end

  local result = M.run(args)
  if result.code ~= 0 then
    return nil
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if ok then
    return data
  end
  return nil
end

---Fetch PR details
---@param number number
---@return Review.PR?
function M.fetch_pr(number)
  return state.prs[number]
end

---Fetch PR diff
---@param number number
---@return string
function M.fetch_pr_diff(number)
  return state.pr_diffs[number] or ""
end

---Fetch conversation comments
---@param number number
---@return Review.Comment[]
function M.fetch_conversation_comments(number)
  return vim.deepcopy(state.conversation_comments[number] or {})
end

---Fetch review comments (code comments)
---@param number number
---@return Review.Comment[]
function M.fetch_review_comments(number)
  return vim.deepcopy(state.review_comments[number] or {})
end

---Fetch reviews (summaries)
---@param number number
---@return Review.Comment[]
function M.fetch_reviews(number)
  return vim.deepcopy(state.reviews[number] or {})
end

---Group comments into threads
---@param comments Review.Comment[]
---@return Review.Comment[]
function M.group_into_threads(comments)
  local threads = {}
  local replies = {}

  for _, comment in ipairs(comments) do
    if comment.in_reply_to_id then
      replies[comment.in_reply_to_id] = replies[comment.in_reply_to_id] or {}
      table.insert(replies[comment.in_reply_to_id], comment)
    else
      threads[comment.github_id or comment.id] = comment
      comment.replies = {}
    end
  end

  for parent_id, thread_replies in pairs(replies) do
    if threads[parent_id] then
      threads[parent_id].replies = thread_replies
    end
  end

  local result = {}
  for _, thread in pairs(threads) do
    table.insert(result, thread)
  end

  return result
end

---Fetch PRs where user is requested reviewer
---@return Review.PR[]
function M.fetch_review_requests()
  return vim.deepcopy(state.review_requests)
end

---Fetch all open PRs
---@return Review.PR[]
function M.fetch_open_prs()
  return vim.deepcopy(state.open_prs)
end

---Submit review (mock - just records the submission)
---@param event "APPROVE" | "REQUEST_CHANGES" | "COMMENT"
function M.submit_review(event)
  -- This would be called with event, records in state.submitted_reviews
  table.insert(state.submitted_reviews, { event = event })
end

---Approve PR
function M.approve()
  M.submit_review("APPROVE")
end

---Request changes
function M.request_changes()
  M.submit_review("REQUEST_CHANGES")
end

---Reply to a comment thread
---@param comment_id number
---@param body string
function M.reply_to_comment(comment_id, body)
  -- Mock implementation - just track the reply
end

---Resolve/unresolve a thread
---@param thread_id number
---@param resolved boolean
function M.resolve_thread(thread_id, resolved)
  -- Mock implementation
end

---Refresh comments
function M.refresh_comments()
  -- Mock implementation
end

---Add conversation comment
function M.add_conversation_comment()
  -- Mock implementation - in real code this opens input
end

-- Module injection helpers

---Install mock into package.loaded, storing original
function M.install()
  original_github = package.loaded["review.integrations.github"]
  package.loaded["review.integrations.github"] = M
end

---Restore original github module
function M.restore()
  if original_github then
    package.loaded["review.integrations.github"] = original_github
    original_github = nil
  else
    package.loaded["review.integrations.github"] = nil
  end
  M.reset()
end

---Get submitted reviews (for test assertions)
---@return table[]
function M.get_submitted_reviews()
  return vim.deepcopy(state.submitted_reviews)
end

return M
