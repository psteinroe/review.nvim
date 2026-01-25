-- GitHub integration for review.nvim (gh CLI wrapper)
-- Handles PR fetching, comments, reviews, and submissions
local M = {}

---@class Review.GithubResult
---@field stdout string
---@field stderr string
---@field code number

---Run gh CLI command synchronously
---@param args string[] gh CLI arguments
---@param opts? {timeout?: number}
---@return Review.GithubResult
function M.run(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ "gh" }, args)
  local result = vim.system(cmd, {
    text = true,
    timeout = opts.timeout,
  }):wait()
  return {
    stdout = result.stdout or "",
    stderr = result.stderr or "",
    code = result.code or -1,
  }
end

---Run gh CLI command asynchronously
---@param args string[] gh CLI arguments
---@param opts? {timeout?: number}
---@param callback fun(result: Review.GithubResult)
function M.run_async(args, opts, callback)
  opts = opts or {}
  local cmd = vim.list_extend({ "gh" }, args)
  vim.system(cmd, {
    text = true,
    timeout = opts.timeout,
  }, function(result)
    vim.schedule(function()
      callback({
        stdout = result.stdout or "",
        stderr = result.stderr or "",
        code = result.code or -1,
      })
    end)
  end)
end

---Check if gh CLI is available and authenticated
---@return boolean
function M.is_available()
  local result = M.run({ "auth", "status" })
  return result.code == 0
end

---Run gh api command
---@param endpoint string API endpoint
---@param opts? {method?: string, fields?: table, raw_fields?: table, jq?: string}
---@return table? data Parsed JSON response or nil on error
function M.api(endpoint, opts)
  opts = opts or {}
  local args = { "api", endpoint }

  if opts.method then
    table.insert(args, "--method")
    table.insert(args, opts.method)
  end

  -- Fields with JSON encoding
  if opts.fields then
    for key, value in pairs(opts.fields) do
      table.insert(args, "-f")
      table.insert(args, key .. "=" .. tostring(value))
    end
  end

  -- Raw fields (for JSON values)
  if opts.raw_fields then
    for key, value in pairs(opts.raw_fields) do
      table.insert(args, "-F")
      if type(value) == "table" then
        table.insert(args, key .. "=" .. vim.json.encode(value))
      else
        table.insert(args, key .. "=" .. tostring(value))
      end
    end
  end

  -- JQ filter
  if opts.jq then
    table.insert(args, "--jq")
    table.insert(args, opts.jq)
  end

  local result = M.run(args)
  if result.code ~= 0 then
    vim.notify("GitHub API error: " .. result.stderr, vim.log.levels.ERROR)
    return nil
  end

  -- Handle empty response
  if vim.trim(result.stdout) == "" then
    return {}
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    vim.notify("Failed to parse GitHub API response", vim.log.levels.ERROR)
    return nil
  end

  return data
end

---Run GraphQL query
---@param query string GraphQL query
---@param variables? table Query variables
---@return table? data Response data or nil on error
function M.graphql(query, variables)
  local args = { "api", "graphql", "-f", "query=" .. query }

  if variables then
    for key, value in pairs(variables) do
      table.insert(args, "-F")
      if type(value) == "table" then
        table.insert(args, key .. "=" .. vim.json.encode(value))
      else
        table.insert(args, key .. "=" .. tostring(value))
      end
    end
  end

  local result = M.run(args)
  if result.code ~= 0 then
    vim.notify("GitHub GraphQL error: " .. result.stderr, vim.log.levels.ERROR)
    return nil
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if ok then
    return data
  end
  return nil
end

---Fetch PR details
---@param number number PR number
---@return Review.PR? pr PR data or nil on error
function M.fetch_pr(number)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    vim.notify("Could not determine repository", vim.log.levels.ERROR)
    return nil
  end

  local endpoint = string.format("repos/%s/%s/pulls/%d", repo.owner, repo.repo, number)
  local data = M.api(endpoint)

  if not data then
    return nil
  end

  return {
    number = data.number,
    title = data.title,
    description = data.body or "",
    author = data.user and data.user.login or "unknown",
    branch = data.head and data.head.ref or "",
    base = data.base and data.base.ref or "",
    created_at = data.created_at,
    updated_at = data.updated_at,
    additions = data.additions or 0,
    deletions = data.deletions or 0,
    changed_files = data.changed_files or 0,
    state = data.state,
    review_decision = data.review_decision,
    url = data.html_url,
  }
end

---Fetch PR diff
---@param number number PR number
---@return string diff Diff output
function M.fetch_pr_diff(number)
  local result = M.run({ "pr", "diff", tostring(number) })
  if result.code ~= 0 then
    vim.notify("Failed to fetch PR diff: " .. result.stderr, vim.log.levels.ERROR)
    return ""
  end
  return result.stdout
end

---Fetch conversation comments (issue comments)
---@param number number PR/issue number
---@return Review.Comment[] comments
function M.fetch_conversation_comments(number)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return {}
  end

  local endpoint = string.format("repos/%s/%s/issues/%d/comments", repo.owner, repo.repo, number)
  local data = M.api(endpoint) or {}

  local comments = {}
  for _, item in ipairs(data) do
    table.insert(comments, {
      id = "gh_conv_" .. tostring(item.id),
      kind = "conversation",
      body = item.body or "",
      author = item.user and item.user.login or "unknown",
      created_at = item.created_at,
      updated_at = item.updated_at,
      github_id = item.id,
    })
  end

  return comments
end

---Fetch review comments (code comments)
---@param number number PR number
---@return Review.Comment[] comments
function M.fetch_review_comments(number)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return {}
  end

  local endpoint = string.format("repos/%s/%s/pulls/%d/comments", repo.owner, repo.repo, number)
  local data = M.api(endpoint) or {}

  local comments = {}
  for _, item in ipairs(data) do
    table.insert(comments, {
      id = "gh_review_" .. tostring(item.id),
      kind = "review",
      body = item.body or "",
      author = item.user and item.user.login or "unknown",
      created_at = item.created_at,
      updated_at = item.updated_at,
      file = item.path,
      line = item.line or item.original_line,
      start_line = item.start_line,
      end_line = item.line or item.original_line,
      side = item.side,
      commit_id = item.commit_id,
      thread_id = item.id,
      in_reply_to_id = item.in_reply_to_id,
      github_id = item.id,
    })
  end

  -- Group into threads
  comments = M.group_into_threads(comments)

  return comments
end

---Fetch reviews (summaries with approve/request changes)
---@param number number PR number
---@return Review.Comment[] reviews
function M.fetch_reviews(number)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return {}
  end

  local endpoint = string.format("repos/%s/%s/pulls/%d/reviews", repo.owner, repo.repo, number)
  local data = M.api(endpoint) or {}

  local comments = {}
  for _, item in ipairs(data) do
    -- Only include reviews with a body (summaries)
    if item.body and item.body ~= "" then
      table.insert(comments, {
        id = "gh_summary_" .. tostring(item.id),
        kind = "review_summary",
        body = item.body,
        author = item.user and item.user.login or "unknown",
        created_at = item.submitted_at,
        review_state = item.state,
        github_id = item.id,
      })
    end
  end

  return comments
end

---Group comments into threads (attach replies to parent comments)
---@param comments Review.Comment[]
---@return Review.Comment[] comments with replies attached
function M.group_into_threads(comments)
  local threads = {}
  local replies = {}

  -- Separate root comments and replies
  for _, comment in ipairs(comments) do
    if comment.in_reply_to_id then
      replies[comment.in_reply_to_id] = replies[comment.in_reply_to_id] or {}
      table.insert(replies[comment.in_reply_to_id], comment)
    else
      threads[comment.github_id] = comment
      comment.replies = {}
    end
  end

  -- Attach replies to their parent threads
  for parent_id, thread_replies in pairs(replies) do
    if threads[parent_id] then
      -- Sort replies by created_at
      table.sort(thread_replies, function(a, b)
        return (a.created_at or "") < (b.created_at or "")
      end)
      threads[parent_id].replies = thread_replies
    end
  end

  -- Convert back to list
  local result = {}
  for _, thread in pairs(threads) do
    table.insert(result, thread)
  end

  -- Sort threads by file and line
  table.sort(result, function(a, b)
    if a.file ~= b.file then
      return (a.file or "") < (b.file or "")
    end
    return (a.line or 0) < (b.line or 0)
  end)

  return result
end

---Fetch all comments for a PR (conversation + review + summaries)
---@param number number PR number
---@return Review.Comment[] all comments
function M.fetch_all_comments(number)
  local conversation = M.fetch_conversation_comments(number)
  local reviews = M.fetch_reviews(number)
  local code_comments = M.fetch_review_comments(number)

  local all = {}
  vim.list_extend(all, conversation)
  vim.list_extend(all, reviews)
  vim.list_extend(all, code_comments)

  return all
end

---Fetch PRs where user is requested as reviewer
---@return Review.PR[] prs
function M.fetch_review_requests()
  local result = M.run({
    "pr",
    "list",
    "--json",
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url",
    "--search",
    "review-requested:@me",
  })
  if result.code ~= 0 then
    return {}
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    return {}
  end

  local prs = {}
  for _, item in ipairs(data) do
    table.insert(prs, {
      number = item.number,
      title = item.title,
      author = item.author and item.author.login or "unknown",
      created_at = item.createdAt,
      branch = item.headRefName,
      base = item.baseRefName,
      additions = item.additions or 0,
      deletions = item.deletions or 0,
      changed_files = item.changedFiles or 0,
      state = item.state,
      url = item.url,
    })
  end

  return prs
end

---Fetch all open PRs in the repository
---@return Review.PR[] prs
function M.fetch_open_prs()
  local result = M.run({
    "pr",
    "list",
    "--json",
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url",
    "--state",
    "open",
  })
  if result.code ~= 0 then
    return {}
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    return {}
  end

  local prs = {}
  for _, item in ipairs(data) do
    table.insert(prs, {
      number = item.number,
      title = item.title,
      author = item.author and item.author.login or "unknown",
      created_at = item.createdAt,
      branch = item.headRefName,
      base = item.baseRefName,
      additions = item.additions or 0,
      deletions = item.deletions or 0,
      changed_files = item.changedFiles or 0,
      state = item.state,
      url = item.url,
    })
  end

  return prs
end

---Add a conversation comment to a PR
function M.add_conversation_comment()
  local state = require("review.core.state")
  if not state.state.pr then
    vim.notify("No PR open", vim.log.levels.ERROR)
    return
  end

  local float = require("review.ui.float")
  float.multiline_input({
    prompt = "Conversation comment",
  }, function(lines)
    if not lines or #lines == 0 then
      return
    end
    local body = table.concat(lines, "\n")

    local git = require("review.integrations.git")
    local repo = git.parse_repo()
    if not repo then
      vim.notify("Could not determine repository", vim.log.levels.ERROR)
      return
    end

    local endpoint = string.format(
      "repos/%s/%s/issues/%d/comments",
      repo.owner,
      repo.repo,
      state.state.pr.number
    )

    local result = M.api(endpoint, { method = "POST", fields = { body = body } })
    if result then
      vim.notify("Comment added", vim.log.levels.INFO)
      M.refresh_comments()
    end
  end)
end

---Submit a review with pending comments
---@param event "APPROVE" | "REQUEST_CHANGES" | "COMMENT"
function M.submit_review(event)
  local state = require("review.core.state")
  if not state.state.pr then
    vim.notify("No PR open", vim.log.levels.ERROR)
    return
  end

  local pending = state.get_pending_comments()
  if #pending == 0 and event == "COMMENT" then
    vim.notify("No pending comments to submit", vim.log.levels.WARN)
    return
  end

  local float = require("review.ui.float")
  float.multiline_input({
    prompt = "Review summary (optional)",
  }, function(lines)
    local body = lines and table.concat(lines, "\n") or ""

    -- Build gh pr review command
    local args = { "pr", "review", tostring(state.state.pr.number) }

    if event == "APPROVE" then
      table.insert(args, "--approve")
    elseif event == "REQUEST_CHANGES" then
      table.insert(args, "--request-changes")
    else
      table.insert(args, "--comment")
    end

    if body ~= "" then
      table.insert(args, "--body")
      table.insert(args, body)
    end

    local result = M.run(args)
    if result.code == 0 then
      vim.notify("Review submitted", vim.log.levels.INFO)

      -- Mark pending comments as submitted
      local comments_module = require("review.core.comments")
      for _, comment in ipairs(pending) do
        comments_module.mark_submitted(comment.id)
      end

      M.refresh_comments()
    else
      vim.notify("Failed to submit review: " .. result.stderr, vim.log.levels.ERROR)
    end
  end)
end

---Approve the current PR
function M.approve()
  M.submit_review("APPROVE")
end

---Request changes on the current PR
function M.request_changes()
  M.submit_review("REQUEST_CHANGES")
end

---Reply to a comment thread
---@param comment_id number GitHub comment ID
---@param body string Reply body
function M.reply_to_comment(comment_id, body)
  local state = require("review.core.state")
  if not state.state.pr then
    vim.notify("No PR open", vim.log.levels.ERROR)
    return
  end

  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    vim.notify("Could not determine repository", vim.log.levels.ERROR)
    return
  end

  local endpoint = string.format(
    "repos/%s/%s/pulls/%d/comments/%d/replies",
    repo.owner,
    repo.repo,
    state.state.pr.number,
    comment_id
  )

  local result = M.api(endpoint, { method = "POST", fields = { body = body } })
  if result then
    vim.notify("Reply added", vim.log.levels.INFO)
    M.refresh_comments()
  end
end

---Prompt for a reply to a comment
---@param comment Review.Comment Comment to reply to
function M.reply_to_comment_prompt(comment)
  if not comment.github_id then
    vim.notify("Cannot reply to local comment", vim.log.levels.WARN)
    return
  end

  local float = require("review.ui.float")
  float.multiline_input({
    prompt = "Reply to @" .. (comment.author or "unknown"),
  }, function(lines)
    if not lines or #lines == 0 then
      return
    end
    local body = table.concat(lines, "\n")
    M.reply_to_comment(comment.github_id, body)
  end)
end

---Resolve or unresolve a review thread
---@param thread_id string GitHub thread node ID
---@param resolved boolean Whether to resolve or unresolve
function M.resolve_thread(thread_id, resolved)
  local state = require("review.core.state")
  if not state.state.pr then
    return
  end

  local mutation = resolved and "resolveReviewThread" or "unresolveReviewThread"
  local query = string.format(
    [[
    mutation {
      %s(input: {threadId: "%s"}) {
        thread { isResolved }
      }
    }
  ]],
    mutation,
    thread_id
  )

  local result = M.run({ "api", "graphql", "-f", "query=" .. query })
  if result.code == 0 then
    vim.notify(resolved and "Thread resolved" or "Thread unresolved", vim.log.levels.INFO)
    M.refresh_comments()
  else
    vim.notify("Failed to update thread: " .. result.stderr, vim.log.levels.ERROR)
  end
end

---Toggle thread resolution state
---@param comment Review.Comment Comment whose thread to toggle
function M.toggle_thread_resolved(comment)
  if not comment.thread_id then
    vim.notify("No thread ID found", vim.log.levels.WARN)
    return
  end

  -- Need to fetch the thread node ID via GraphQL to resolve/unresolve
  -- For now, use the REST API approach if available
  local new_resolved = not comment.resolved
  M.resolve_thread(tostring(comment.thread_id), new_resolved)
end

---Refresh comments from GitHub
function M.refresh_comments()
  local state = require("review.core.state")
  if not state.state.pr then
    return
  end

  local pr_number = state.state.pr.number

  -- Keep local (pending) comments
  local local_comments = vim.tbl_filter(function(c)
    return c.kind == "local"
  end, state.state.comments)

  -- Fetch fresh data from GitHub
  local conversation = M.fetch_conversation_comments(pr_number)
  local reviews = M.fetch_reviews(pr_number)
  local code_comments = M.fetch_review_comments(pr_number)

  -- Merge all comments
  state.state.comments = {}
  vim.list_extend(state.state.comments, conversation)
  vim.list_extend(state.state.comments, reviews)
  vim.list_extend(state.state.comments, code_comments)
  vim.list_extend(state.state.comments, local_comments)

  -- Update file comment counts
  M.update_file_comment_counts()

  -- Refresh UI
  local ok_tree, file_tree = pcall(require, "review.ui.file_tree")
  if ok_tree then
    file_tree.render()
  end

  local ok_signs, signs = pcall(require, "review.ui.signs")
  if ok_signs then
    signs.refresh()
  end

  local ok_vt, virtual_text = pcall(require, "review.ui.virtual_text")
  if ok_vt then
    virtual_text.refresh()
  end

  if state.state.panel_open then
    local ok_panel, panel = pcall(require, "review.ui.panel")
    if ok_panel then
      panel.refresh()
    end
  end
end

---Update comment counts for each file in state
function M.update_file_comment_counts()
  local state = require("review.core.state")

  -- Reset counts
  for _, file in ipairs(state.state.files) do
    file.comment_count = 0
  end

  -- Count comments per file
  local counts = {}
  for _, comment in ipairs(state.state.comments) do
    if comment.file then
      counts[comment.file] = (counts[comment.file] or 0) + 1
    end
  end

  -- Update file data
  for _, file in ipairs(state.state.files) do
    file.comment_count = counts[file.path] or 0
  end
end

---Create a code comment on a PR (not via review, direct comment)
---@param file string File path
---@param line number Line number
---@param body string Comment body
---@param opts? {side?: "LEFT"|"RIGHT", commit_id?: string}
function M.create_code_comment(file, line, body, opts)
  opts = opts or {}
  local state = require("review.core.state")
  if not state.state.pr then
    vim.notify("No PR open", vim.log.levels.ERROR)
    return
  end

  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    vim.notify("Could not determine repository", vim.log.levels.ERROR)
    return
  end

  local endpoint = string.format(
    "repos/%s/%s/pulls/%d/comments",
    repo.owner,
    repo.repo,
    state.state.pr.number
  )

  local fields = {
    body = body,
    path = file,
    line = tostring(line),
    side = opts.side or "RIGHT",
  }

  if opts.commit_id then
    fields.commit_id = opts.commit_id
  end

  local result = M.api(endpoint, { method = "POST", fields = fields })
  if result then
    vim.notify("Comment created", vim.log.levels.INFO)
    M.refresh_comments()
  end
end

---Checkout a PR locally
---@param number number PR number
---@return boolean success
function M.checkout_pr(number)
  local result = M.run({ "pr", "checkout", tostring(number) })
  if result.code == 0 then
    vim.notify(string.format("Checked out PR #%d", number), vim.log.levels.INFO)
    return true
  else
    vim.notify("Failed to checkout PR: " .. result.stderr, vim.log.levels.ERROR)
    return false
  end
end

---Get the current PR number if on a PR branch
---@return number? pr_number
function M.get_current_pr_number()
  local result = M.run({
    "pr",
    "view",
    "--json",
    "number",
    "--jq",
    ".number",
  })
  if result.code == 0 then
    return tonumber(vim.trim(result.stdout))
  end
  return nil
end

---Open PR in web browser
---@param number? number PR number (uses current if not provided)
function M.open_in_browser(number)
  local args = { "pr", "view", "--web" }
  if number then
    table.insert(args, tostring(number))
  end

  local result = M.run(args)
  if result.code ~= 0 then
    vim.notify("Failed to open PR in browser: " .. result.stderr, vim.log.levels.ERROR)
  end
end

return M
