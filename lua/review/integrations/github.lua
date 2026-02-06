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
---@param opts? {method?: string, fields?: table, raw_fields?: table, jq?: string, paginate?: boolean, silent?: boolean}
---@return table? data Parsed JSON response or nil on error
function M.api(endpoint, opts)
  opts = opts or {}
  local args = { "api", endpoint }

  if opts.method then
    table.insert(args, "--method")
    table.insert(args, opts.method)
  end

  -- Pagination support - fetches all pages automatically
  if opts.paginate then
    table.insert(args, "--paginate")
  end

  -- Fields with JSON encoding
  if opts.fields then
    for key, value in pairs(opts.fields) do
      table.insert(args, "-f")
      table.insert(args, key .. "=" .. tostring(value))
    end
  end

  -- Raw fields (for JSON values - numbers, booleans, arrays, objects)
  if opts.raw_fields then
    for key, value in pairs(opts.raw_fields) do
      table.insert(args, "-F")
      -- For -F, gh parses the value as JSON, so numbers should not be quoted
      if type(value) == "table" then
        table.insert(args, key .. "=" .. vim.json.encode(value))
      elseif type(value) == "number" then
        table.insert(args, key .. "=" .. value)
      elseif type(value) == "boolean" then
        table.insert(args, key .. "=" .. (value and "true" or "false"))
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
    -- Only show errors if not silent and not a 404 (which is often expected)
    if not opts.silent and not result.stderr:match("404") and not result.stderr:match("Not Found") then
      vim.notify("GitHub API error: " .. result.stderr, vim.log.levels.ERROR)
    end
    return nil
  end

  -- Handle empty response
  if vim.trim(result.stdout) == "" then
    return {}
  end

  -- When paginating, gh returns newline-separated JSON arrays that need merging
  if opts.paginate then
    local all_items = {}
    for line in result.stdout:gmatch("[^\n]+") do
      local ok, page_data = pcall(vim.json.decode, line)
      if ok and type(page_data) == "table" then
        if vim.islist(page_data) then
          vim.list_extend(all_items, page_data)
        else
          table.insert(all_items, page_data)
        end
      end
    end
    return all_items
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    vim.notify("Failed to parse GitHub API response", vim.log.levels.ERROR)
    return nil
  end

  return data
end

---Build args for gh api command (shared between sync and async)
---@param endpoint string API endpoint
---@param opts? {method?: string, fields?: table, raw_fields?: table, jq?: string}
---@return string[] args
local function build_api_args(endpoint, opts)
  opts = opts or {}
  local args = { "api", endpoint }

  if opts.method then
    table.insert(args, "--method")
    table.insert(args, opts.method)
  end

  if opts.fields then
    for key, value in pairs(opts.fields) do
      table.insert(args, "-f")
      table.insert(args, key .. "=" .. tostring(value))
    end
  end

  if opts.raw_fields then
    for key, value in pairs(opts.raw_fields) do
      table.insert(args, "-F")
      if type(value) == "table" then
        table.insert(args, key .. "=" .. vim.json.encode(value))
      elseif type(value) == "number" then
        table.insert(args, key .. "=" .. value)
      elseif type(value) == "boolean" then
        table.insert(args, key .. "=" .. (value and "true" or "false"))
      else
        table.insert(args, key .. "=" .. tostring(value))
      end
    end
  end

  if opts.jq then
    table.insert(args, "--jq")
    table.insert(args, opts.jq)
  end

  return args
end

---Run gh api command asynchronously
---@param endpoint string API endpoint
---@param opts? {method?: string, fields?: table, raw_fields?: table, jq?: string}
---@param callback? fun(data: table?, err: string?) Called with result or error
function M.api_async(endpoint, opts, callback)
  local args = build_api_args(endpoint, opts)

  M.run_async(args, {}, function(result)
    if result.code ~= 0 then
      if callback then
        callback(nil, result.stderr)
      end
      return
    end

    if vim.trim(result.stdout) == "" then
      if callback then
        callback({}, nil)
      end
      return
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
      if callback then
        callback(nil, "Failed to parse response")
      end
      return
    end

    if callback then
      callback(data, nil)
    end
  end)
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
  -- Use gh pr view which handles repo context correctly
  local result = M.run({
    "pr",
    "view",
    tostring(number),
    "--json",
    "number,title,body,author,headRefName,baseRefName,headRefOid,createdAt,updatedAt,additions,deletions,changedFiles,state,reviewDecision,url",
  })

  if result.code ~= 0 then
    -- Don't show error here - let caller handle it
    return nil
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    return nil
  end

  return {
    number = data.number,
    title = data.title,
    description = data.body or "",
    author = data.author and data.author.login or "unknown",
    branch = data.headRefName or "",
    base = data.baseRefName or "",
    head_sha = data.headRefOid,
    created_at = data.createdAt,
    updated_at = data.updatedAt,
    additions = data.additions or 0,
    deletions = data.deletions or 0,
    changed_files = data.changedFiles or 0,
    state = data.state and data.state:lower() or "open",
    review_decision = data.reviewDecision,
    url = data.url,
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

---Fetch file content from a PR's head commit via GitHub API
---@param pr_number number PR number
---@param file_path string File path
---@return string? content File content or nil on error
function M.fetch_file_content(pr_number, file_path)
  local state = require("review.core.state")
  local pr = state.state.pr
  if not pr then
    return nil
  end

  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return nil
  end

  -- Use head_sha which works for both forks and same-repo PRs
  local ref = pr.head_sha or pr.branch
  if not ref then
    return nil
  end

  -- Fetch file content via GitHub API using the commit SHA
  -- URL-encode the path for the API
  local encoded_path = file_path:gsub("([^%w%-_%.~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  local endpoint = string.format("repos/%s/%s/contents/%s?ref=%s", repo.owner, repo.repo, encoded_path, ref)
  local data = M.api(endpoint)

  if data and data.content then
    -- Content is base64 encoded
    local content_clean = data.content:gsub("%s+", "") -- Remove all whitespace including newlines
    local ok, decoded = pcall(vim.base64.decode, content_clean)
    if ok then
      return decoded
    end
  elseif data and data.download_url then
    -- Large files have download_url instead - fetch via curl
    local curl_result = vim.fn.system({ "curl", "-sL", data.download_url })
    if vim.v.shell_error == 0 then
      return curl_result
    end
  end

  return nil
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
  local data = M.api(endpoint, { paginate = true }) or {}

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
  local data = M.api(endpoint, { paginate = true }) or {}

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
  local data = M.api(endpoint, { paginate = true }) or {}

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
      local parent_id = tostring(comment.in_reply_to_id)
      replies[parent_id] = replies[parent_id] or {}
      table.insert(replies[parent_id], comment)
    else
      local id = tostring(comment.github_id)
      threads[id] = comment
      comment.replies = {}
    end
  end

  -- Attach replies to their parent threads
  for parent_id, thread_replies in pairs(replies) do
    if threads[parent_id] then
      -- Sort replies by created_at
      table.sort(thread_replies, function(a, b)
        local a_time = tostring(a.created_at or "")
        local b_time = tostring(b.created_at or "")
        return a_time < b_time
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
    local a_file = tostring(a.file or "")
    local b_file = tostring(b.file or "")
    if a_file ~= b_file then
      return a_file < b_file
    end
    local a_line = tonumber(a.line) or 0
    local b_line = tonumber(b.line) or 0
    return a_line < b_line
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

---Get current GitHub username
---@return string|nil
function M.get_current_user()
  if M._current_user then
    return M._current_user
  end
  local result = M.run({ "api", "user", "--jq", ".login" })
  if result.code == 0 then
    M._current_user = vim.trim(result.stdout)
    return M._current_user
  end
  return nil
end

---Extract user's review status from PR reviews
---@param reviews table[] List of reviews from GitHub API
---@param username string Current user's login
---@return string|nil status One of: "APPROVED", "CHANGES_REQUESTED", "COMMENTED", "PENDING", nil
local function get_user_review_status(reviews, username)
  if not reviews or not username then
    return nil
  end
  -- Find most recent review by this user
  for i = #reviews, 1, -1 do
    local review = reviews[i]
    if review.author and review.author.login == username then
      return review.state
    end
  end
  return nil
end

---Fetch PRs where user is requested as reviewer
---@return Review.PR[] prs
function M.fetch_review_requests()
  local result = M.run({
    "pr",
    "list",
    "--json",
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url,reviews",
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

  local username = M.get_current_user()
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
      review_status = get_user_review_status(item.reviews, username),
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
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url,reviews",
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

  local username = M.get_current_user()
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
      review_status = get_user_review_status(item.reviews, username),
    })
  end

  return prs
end

---Add a conversation comment to a PR (async)
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

    vim.notify("Sending comment...", vim.log.levels.INFO)
    M.api_async(endpoint, { method = "POST", fields = { body = body } }, function(data, err)
      if err then
        vim.notify("Failed to add comment: " .. err, vim.log.levels.ERROR)
      else
        vim.notify("Comment added", vim.log.levels.INFO)
        M.refresh_comments()
      end
    end)
  end)
end

---Get the PR node ID (required for GraphQL mutations)
---@param pr_number number
---@return string? node_id
function M.get_pr_node_id(pr_number)
  local result = M.run({
    "pr", "view", tostring(pr_number),
    "--json", "id",
    "--jq", ".id",
  })
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

---Parse a unified diff to extract valid commentable line numbers per file (RIGHT side)
---@param diff_text string Raw unified diff output
---@return table<string, table<number, boolean>> Map of file path → set of valid line numbers
local function parse_diff_valid_lines(diff_text)
  local valid = {}
  local current_file = nil
  local new_line = 0

  for line in diff_text:gmatch("[^\n]*\n?") do
    -- Strip trailing newline/carriage return
    line = line:gsub("[\r\n]+$", "")

    -- New file header: diff --git a/path b/path
    local file_path = line:match("^diff %-%-git a/.+ b/(.+)$")
    if file_path then
      current_file = file_path
      new_line = 0 -- Reset line counter between files
      if not valid[current_file] then
        valid[current_file] = {}
      end
    end

    -- Skip diff metadata headers before checking content
    if line:match("^index ") or line:match("^%-%-%- ") or line:match("^%+%+%+ ") or line:match("^new file") or line:match("^deleted file") or line:match("^old mode") or line:match("^new mode") or line:match("^similarity") or line:match("^rename ") then
      -- Diff metadata - skip entirely
    else
      -- Hunk header: @@ -old,count +new,count @@
      local new_start = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
      if new_start then
        new_line = tonumber(new_start)
      elseif current_file and new_line > 0 then
        local first_char = line:sub(1, 1)
        if first_char == "+" then
          -- Added line: valid on RIGHT side
          valid[current_file][new_line] = true
          new_line = new_line + 1
        elseif first_char == "-" then
          -- Deleted line: only on LEFT side, don't increment new_line
        elseif first_char == " " then
          -- Context line: valid on RIGHT side
          valid[current_file][new_line] = true
          new_line = new_line + 1
        elseif first_char == "\\" then
          -- "\ No newline at end of file" - skip
        end
      end
    end
  end

  return valid
end

---Submit a review with pending comments using GraphQL
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

  -- Fetch the PR diff to validate which lines are commentable on GitHub
  local pr_diff = M.fetch_pr_diff(state.state.pr.number)
  local valid_lines = parse_diff_valid_lines(pr_diff)

  -- Pre-compute which comments will be submitted vs skipped
  local submittable = {}
  local skipped = {}
  for _, comment in ipairs(pending) do
    if comment.file and comment.line then
      local file_info = state.find_file(comment.file)
      if file_info and (file_info.provenance == "local" or file_info.provenance == "uncommitted") then
        table.insert(skipped, { comment = comment, reason = "local/uncommitted file" })
      elseif valid_lines[comment.file] and valid_lines[comment.file][comment.line] then
        table.insert(submittable, comment)
      elseif valid_lines[comment.file] then
        table.insert(skipped, { comment = comment, reason = "line not in PR diff" })
      elseif pr_diff ~= "" then
        table.insert(skipped, { comment = comment, reason = "file not in PR diff" })
      else
        -- Could not fetch PR diff, try submitting anyway
        table.insert(submittable, comment)
      end
    end
  end

  -- Build summary lines (# prefix = stripped on submit, like git commit messages)
  local summary_lines = {}
  local event_labels = {
    APPROVE = "Approve",
    REQUEST_CHANGES = "Request Changes",
    COMMENT = "Comment",
  }
  table.insert(summary_lines, "")
  table.insert(summary_lines, string.format("# %s — PR #%d: %s",
    event_labels[event] or event,
    state.state.pr.number,
    state.state.pr.title or ""))
  table.insert(summary_lines, "#")

  if #submittable > 0 then
    table.insert(summary_lines, string.format("# %d comment(s) to submit:", #submittable))
    for _, c in ipairs(submittable) do
      local type_str = c.type and c.type ~= "note" and string.format("[%s] ", c.type) or ""
      local preview = c.body:gsub("\n", " ")
      if #preview > 50 then
        preview = preview:sub(1, 47) .. "..."
      end
      table.insert(summary_lines, string.format("#   %s:%d  %s%s", c.file, c.line, type_str, preview))
    end
  else
    table.insert(summary_lines, "# No comments to submit")
  end

  if #skipped > 0 then
    table.insert(summary_lines, "#")
    table.insert(summary_lines, string.format("# %d comment(s) skipped:", #skipped))
    for _, s in ipairs(skipped) do
      local c = s.comment
      local preview = c.body:gsub("\n", " ")
      if #preview > 40 then
        preview = preview:sub(1, 37) .. "..."
      end
      local detail = s.reason
      -- Show valid line ranges when a line isn't in the diff
      if s.reason == "line not in PR diff" and valid_lines[c.file] then
        local sorted = {}
        for ln in pairs(valid_lines[c.file]) do
          table.insert(sorted, ln)
        end
        table.sort(sorted)
        if #sorted > 0 then
          -- Compress into ranges like "1-5, 10-15"
          local ranges = {}
          local range_start = sorted[1]
          local range_end = sorted[1]
          for i = 2, #sorted do
            if sorted[i] == range_end + 1 then
              range_end = sorted[i]
            else
              if range_start == range_end then
                table.insert(ranges, tostring(range_start))
              else
                table.insert(ranges, range_start .. "-" .. range_end)
              end
              range_start = sorted[i]
              range_end = sorted[i]
            end
          end
          if range_start == range_end then
            table.insert(ranges, tostring(range_start))
          else
            table.insert(ranges, range_start .. "-" .. range_end)
          end
          detail = detail .. string.format(" (valid: %s)", table.concat(ranges, ", "))
        end
      end
      table.insert(summary_lines, string.format("#   %s:%d  %s (%s)", c.file, c.line, preview, detail))
    end
  end

  if #submittable == 0 and #skipped > 0 then
    table.insert(summary_lines, "#")
    table.insert(summary_lines, "# NOTE: GitHub only allows comments on lines visible in the PR diff")
    table.insert(summary_lines, "# (changed lines + surrounding context). Comments on other lines")
    table.insert(summary_lines, "# cannot be submitted as review comments.")
  end

  table.insert(summary_lines, "#")
  table.insert(summary_lines, "# Lines starting with # are ignored.")
  table.insert(summary_lines, "# Write your review summary above, then Ctrl+S to submit.")

  local float = require("review.ui.float")
  float.multiline_input({
    prompt = event_labels[event] or "Review",
    default = table.concat(summary_lines, "\n"),
    filetype = "gitcommit",
  }, function(lines)
    -- Strip # comment lines and build body
    local body_lines = {}
    if lines then
      for _, line in ipairs(lines) do
        if not line:match("^#") then
          table.insert(body_lines, line)
        end
      end
    end
    -- Trim leading/trailing blank lines
    while #body_lines > 0 and body_lines[1]:match("^%s*$") do
      table.remove(body_lines, 1)
    end
    while #body_lines > 0 and body_lines[#body_lines]:match("^%s*$") do
      table.remove(body_lines)
    end
    local body = table.concat(body_lines, "\n")

    -- Get PR node ID for GraphQL
    local pr_node_id = M.get_pr_node_id(state.state.pr.number)
    if not pr_node_id then
      vim.notify("Could not get PR node ID", vim.log.levels.ERROR)
      return
    end

    -- Build threads array for GraphQL
    local gql_threads = {}
    for _, comment in ipairs(submittable) do
      local comment_body = comment.body
      if comment.type and comment.type ~= "note" then
        local type_prefix = {
          issue = "**Issue:** ",
          suggestion = "**Suggestion:** ",
          praise = "**Praise:** ",
        }
        comment_body = (type_prefix[comment.type] or "") .. comment_body
      end

      table.insert(gql_threads, {
        path = comment.file,
        line = comment.line,
        side = "RIGHT",
        body = comment_body,
      })
    end

    if #skipped > 0 then
      local reasons = {}
      for _, s in ipairs(skipped) do
        reasons[s.reason] = (reasons[s.reason] or 0) + 1
      end
      local parts = {}
      for reason, count in pairs(reasons) do
        table.insert(parts, string.format("%d %s", count, reason))
      end
      vim.notify("Skipped: " .. table.concat(parts, ", "), vim.log.levels.WARN)
    end

    -- If all comments were skipped and no body, nothing to submit for COMMENT event
    if #gql_threads == 0 and (body == nil or body == "") and event == "COMMENT" then
      vim.notify("No submittable comments — all skipped", vim.log.levels.WARN)
      return
    end

    -- Map event to GraphQL enum
    local gql_event = "COMMENT"
    if event == "APPROVE" then
      gql_event = "APPROVE"
    elseif event == "REQUEST_CHANGES" then
      gql_event = "REQUEST_CHANGES"
    end

    -- Build GraphQL mutation using threads (supports line numbers)
    local mutation = [[
      mutation($prId: ID!, $body: String, $event: PullRequestReviewEvent!, $threads: [DraftPullRequestReviewThread!]) {
        addPullRequestReview(input: {
          pullRequestId: $prId
          body: $body
          event: $event
          threads: $threads
        }) {
          pullRequestReview {
            id
            state
          }
        }
      }
    ]]

    -- Build complete request body as JSON
    local request_body = {
      query = mutation,
      variables = {
        prId = pr_node_id,
        body = body ~= "" and body or nil,
        event = gql_event,
        threads = #gql_threads > 0 and gql_threads or nil,
      },
    }

    -- Send via stdin to ensure proper JSON encoding
    local args = { "api", "graphql", "--input", "-" }
    local json_body = vim.json.encode(request_body)

    local cmd = vim.list_extend({ "gh" }, args)
    local proc = vim.system(cmd, {
      text = true,
      stdin = json_body,
    }):wait()

    local result = {
      code = proc.code,
      stdout = proc.stdout or "",
      stderr = proc.stderr or "",
    }
    -- Check for GraphQL errors in response body (can occur even with exit code 0)
    local has_gql_errors = false
    if result.stdout and result.stdout:match("errors") then
      local ok, data = pcall(vim.json.decode, result.stdout)
      if ok and data.errors and #data.errors > 0 then
        has_gql_errors = true
      end
    end

    if result.code == 0 and not has_gql_errors then
      -- Mark only the submitted comments
      local comments_module = require("review.core.comments")
      for _, comment in ipairs(submittable) do
        comments_module.mark_submitted(comment.id)
      end

      vim.notify(string.format("Review submitted with %d comment(s)", #gql_threads), vim.log.levels.INFO)
      M.refresh_comments()

      -- Prompt for next PR after APPROVE or REQUEST_CHANGES
      if event == "APPROVE" or event == "REQUEST_CHANGES" then
        M.prompt_next_pr(state.state.pr.number)
      end
    else
      -- Parse error for better message
      local err = result.stderr or "Unknown error"
      if result.stdout and result.stdout:match("errors") then
        local ok, data = pcall(vim.json.decode, result.stdout)
        if ok and data.errors then
          local msgs = {}
          for _, e in ipairs(data.errors) do
            table.insert(msgs, e.message or "Unknown error")
          end
          err = table.concat(msgs, "; ")
        end
      end
      vim.notify("Failed to submit review: " .. err, vim.log.levels.ERROR)
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

---Submit comments without approving or requesting changes
function M.comment()
  M.submit_review("COMMENT")
end

---Fetch the next unreviewed PR from review requests
---@param exclude_number? number PR number to exclude (current PR)
---@return Review.PR|nil pr The next unreviewed PR, or nil if none
function M.fetch_next_unreviewed_pr(exclude_number)
  local prs = M.fetch_review_requests()
  for _, pr in ipairs(prs) do
    -- Skip current PR and already reviewed PRs
    if pr.number ~= exclude_number and not pr.review_status then
      return pr
    end
  end
  return nil
end

---Prompt user to open next PR after review submission
---@param current_pr_number number The PR that was just reviewed
function M.prompt_next_pr(current_pr_number)
  vim.schedule(function()
    local next_pr = M.fetch_next_unreviewed_pr(current_pr_number)
    if not next_pr then
      vim.notify("All review requests completed!", vim.log.levels.INFO)
      return
    end

    vim.ui.select(
      { "Yes", "No" },
      {
        prompt = string.format("Open next PR? #%d %s (@%s)",
          next_pr.number, next_pr.title or "", next_pr.author or ""),
      },
      function(choice)
        if choice == "Yes" then
          -- Close current review and open next
          require("review").quit()
          vim.schedule(function()
            require("review").open_pr(next_pr.number)
          end)
        end
      end
    )
  end)
end

---Reply to a comment thread (async)
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

  vim.notify("Sending reply...", vim.log.levels.INFO)
  M.api_async(endpoint, { method = "POST", fields = { body = body } }, function(data, err)
    if err then
      vim.notify("Failed to add reply: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("Reply added", vim.log.levels.INFO)
      M.refresh_comments()
    end
  end)
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

---Resolve or unresolve a review thread (async)
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

  local status_msg = resolved and "Resolving..." or "Unresolving..."
  vim.notify(status_msg, vim.log.levels.INFO)

  M.run_async({ "api", "graphql", "-f", "query=" .. query }, {}, function(result)
    if result.code == 0 then
      vim.notify(resolved and "Thread resolved" or "Thread unresolved", vim.log.levels.INFO)
      M.refresh_comments()
    else
      vim.notify("Failed to update thread: " .. result.stderr, vim.log.levels.ERROR)
    end
  end)
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

-- ============================================================================
-- Reactions
-- ============================================================================

---@alias Review.ReactionContent "+1" | "-1" | "laugh" | "confused" | "heart" | "hooray" | "rocket" | "eyes"

---@class Review.Reaction
---@field id number Reaction ID
---@field content Review.ReactionContent Reaction type
---@field user string Username who reacted

---Available reaction emojis
M.REACTION_EMOJIS = {
  ["+1"] = "👍",
  ["-1"] = "👎",
  ["laugh"] = "😄",
  ["confused"] = "😕",
  ["heart"] = "❤️",
  ["hooray"] = "🎉",
  ["rocket"] = "🚀",
  ["eyes"] = "👀",
}

---List of valid reaction content types
M.REACTION_CONTENTS = { "+1", "-1", "laugh", "hooray", "confused", "heart", "rocket", "eyes" }

---Format reactions for display
---@param reactions Review.Reaction[]|nil
---@return string
function M.format_reactions(reactions)
  if not reactions or #reactions == 0 then
    return ""
  end

  -- Count reactions by type
  local counts = {}
  for _, r in ipairs(reactions) do
    counts[r.content] = (counts[r.content] or 0) + 1
  end

  -- Format with emojis
  local parts = {}
  for content, count in pairs(counts) do
    local emoji = M.REACTION_EMOJIS[content] or content
    if count > 1 then
      table.insert(parts, emoji .. " " .. count)
    else
      table.insert(parts, emoji)
    end
  end

  return table.concat(parts, " ")
end

---Get reactions for a review comment
---@param comment_id number GitHub comment ID
---@return Review.Reaction[]
function M.get_comment_reactions(comment_id)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return {}
  end

  local endpoint = string.format("repos/%s/%s/pulls/comments/%d/reactions", repo.owner, repo.repo, comment_id)
  local data = M.api(endpoint) or {}

  local reactions = {}
  for _, item in ipairs(data) do
    table.insert(reactions, {
      id = item.id,
      content = item.content,
      user = item.user and item.user.login or "unknown",
    })
  end

  return reactions
end

---Add a reaction to a review comment (async)
---@param comment_id number GitHub comment ID
---@param content Review.ReactionContent Reaction type
---@param callback? fun(success: boolean) Optional callback
function M.add_reaction(comment_id, content, callback)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    vim.notify("Could not determine repository", vim.log.levels.ERROR)
    if callback then callback(false) end
    return
  end

  local emoji = M.REACTION_EMOJIS[content] or content
  local endpoint = string.format("repos/%s/%s/pulls/comments/%d/reactions", repo.owner, repo.repo, comment_id)

  M.api_async(endpoint, {
    method = "POST",
    fields = { content = content },
  }, function(data, err)
    if err then
      vim.notify("Failed to add reaction: " .. err, vim.log.levels.ERROR)
      if callback then callback(false) end
    else
      vim.notify("Added " .. emoji, vim.log.levels.INFO)
      if callback then callback(true) end
    end
  end)
end

---Remove a reaction from a review comment (async)
---@param comment_id number GitHub comment ID
---@param reaction_id number Reaction ID
---@param callback? fun(success: boolean) Optional callback
function M.remove_reaction(comment_id, reaction_id, callback)
  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    vim.notify("Could not determine repository", vim.log.levels.ERROR)
    if callback then callback(false) end
    return
  end

  local endpoint = string.format(
    "repos/%s/%s/pulls/comments/%d/reactions/%d",
    repo.owner, repo.repo, comment_id, reaction_id
  )

  M.run_async({ "api", endpoint, "--method", "DELETE" }, {}, function(result)
    if result.code == 0 then
      vim.notify("Removed reaction", vim.log.levels.INFO)
      if callback then callback(true) end
    else
      vim.notify("Failed to remove reaction: " .. result.stderr, vim.log.levels.ERROR)
      if callback then callback(false) end
    end
  end)
end

---Show reaction picker for a comment
---@param comment Review.Comment Comment to react to
function M.pick_reaction(comment)
  if not comment.github_id then
    vim.notify("Cannot react to local comment", vim.log.levels.WARN)
    return
  end

  local choices = {}
  for content, emoji in pairs(M.REACTION_EMOJIS) do
    table.insert(choices, { label = emoji .. " " .. content, content = content })
  end

  vim.ui.select(choices, {
    prompt = "Select reaction:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      M.add_reaction(comment.github_id, choice.content)
    end
  end)
end

---Toggle a reaction on a comment
---@param comment Review.Comment Comment to toggle reaction on
---@param content Review.ReactionContent Reaction type
function M.toggle_reaction(comment, content)
  if not comment.github_id then
    vim.notify("Cannot react to local comment", vim.log.levels.WARN)
    return
  end

  -- Get current reactions to see if user already reacted
  local reactions = M.get_comment_reactions(comment.github_id)

  -- Get current user
  local current_user = M.get_current_user()

  -- Check if user already reacted with this content
  for _, reaction in ipairs(reactions) do
    if reaction.content == content and reaction.user == current_user then
      -- Remove the reaction
      M.remove_reaction(comment.github_id, reaction.id)
      return
    end
  end

  -- Add the reaction
  M.add_reaction(comment.github_id, content)
end

---Get the current authenticated user
---@return string? username
function M.get_current_user()
  local result = M.run({ "api", "user", "--jq", ".login" })
  if result.code == 0 then
    return vim.trim(result.stdout)
  end
  return nil
end

-- ============================================================================
-- Fork PR Support
-- ============================================================================

---@class Review.ForkInfo
---@field is_fork boolean Whether PR is from a fork
---@field head_repo_owner? string Fork owner username
---@field head_repo_url? string Fork repository URL
---@field head_branch string Head branch name
---@field head_label string Full ref (owner:branch for forks)

---Fetch detailed PR info including fork information
---@param number number PR number
---@return Review.ForkInfo?
function M.fetch_fork_info(number)
  local result = M.run({
    "pr",
    "view",
    tostring(number),
    "--json",
    "headRefName,headRepositoryOwner,headRepository,isCrossRepository",
  })

  if result.code ~= 0 then
    return nil
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    return nil
  end

  local is_fork = data.isCrossRepository or false
  local head_branch = data.headRefName or ""
  local head_repo_owner = nil
  local head_repo_url = nil
  local head_label = head_branch

  if is_fork and data.headRepositoryOwner and data.headRepository then
    head_repo_owner = data.headRepositoryOwner.login
    head_repo_url = string.format(
      "https://github.com/%s/%s.git",
      head_repo_owner,
      data.headRepository.name
    )
    head_label = head_repo_owner .. ":" .. head_branch
  end

  return {
    is_fork = is_fork,
    head_repo_owner = head_repo_owner,
    head_repo_url = head_repo_url,
    head_branch = head_branch,
    head_label = head_label,
  }
end

---Setup remote for a fork PR
---@param fork_info Review.ForkInfo Fork information
---@return boolean success
function M.setup_fork_remote(fork_info)
  if not fork_info.is_fork or not fork_info.head_repo_owner or not fork_info.head_repo_url then
    return true -- Not a fork, nothing to do
  end

  local remote_name = "fork-" .. fork_info.head_repo_owner
  local git = require("review.integrations.git")

  -- Check if remote already exists
  local result = git.run({ "remote", "get-url", remote_name })
  if result.code == 0 then
    -- Remote exists, verify URL matches
    local existing_url = vim.trim(result.stdout)
    if existing_url == fork_info.head_repo_url then
      return true -- Already set up correctly
    end
    -- Update URL if different
    result = git.run({ "remote", "set-url", remote_name, fork_info.head_repo_url })
    if result.code ~= 0 then
      vim.notify("Failed to update fork remote URL: " .. result.stderr, vim.log.levels.ERROR)
      return false
    end
  else
    -- Add new remote
    result = git.run({ "remote", "add", remote_name, fork_info.head_repo_url })
    if result.code ~= 0 then
      vim.notify("Failed to add fork remote: " .. result.stderr, vim.log.levels.ERROR)
      return false
    end
  end

  -- Fetch from the fork remote
  vim.notify("Fetching from fork remote: " .. remote_name, vim.log.levels.INFO)
  result = git.run({ "fetch", remote_name, fork_info.head_branch })
  if result.code ~= 0 then
    vim.notify("Failed to fetch from fork: " .. result.stderr, vim.log.levels.WARN)
    -- Try fetching all refs
    result = git.run({ "fetch", remote_name })
    if result.code ~= 0 then
      vim.notify("Failed to fetch fork remote: " .. result.stderr, vim.log.levels.ERROR)
      return false
    end
  end

  return true
end

---Checkout a PR (with fork support)
---@param number number PR number
---@return boolean success
function M.checkout_pr_with_fork_support(number)
  -- Get fork info first
  local fork_info = M.fetch_fork_info(number)

  if fork_info and fork_info.is_fork then
    -- Setup fork remote
    if not M.setup_fork_remote(fork_info) then
      vim.notify("Failed to setup fork remote, trying gh pr checkout anyway", vim.log.levels.WARN)
    end
  end

  -- Use gh pr checkout which handles most cases
  return M.checkout_pr(number)
end

---Get diff for a fork PR
---@param number number PR number
---@param fork_info Review.ForkInfo Fork information
---@return string diff
function M.get_fork_pr_diff(number, fork_info)
  if not fork_info.is_fork then
    return M.fetch_pr_diff(number)
  end

  local git = require("review.integrations.git")
  local remote_name = "fork-" .. fork_info.head_repo_owner
  local ref = remote_name .. "/" .. fork_info.head_branch

  -- Try to get diff against base
  local state_module = require("review.core.state")
  local base = state_module.state.base or "origin/main"

  local result = git.run({ "diff", base .. "..." .. ref })
  if result.code == 0 then
    return result.stdout
  end

  -- Fallback to gh pr diff
  return M.fetch_pr_diff(number)
end

---Clean up fork remotes that are no longer needed
function M.cleanup_fork_remotes()
  local git = require("review.integrations.git")

  local result = git.run({ "remote" })
  if result.code ~= 0 then
    return
  end

  local remotes = vim.split(result.stdout, "\n")
  local removed = 0

  for _, remote in ipairs(remotes) do
    if remote:match("^fork%-") then
      local remove_result = git.run({ "remote", "remove", remote })
      if remove_result.code == 0 then
        removed = removed + 1
      end
    end
  end

  if removed > 0 then
    vim.notify(string.format("Cleaned up %d fork remote(s)", removed), vim.log.levels.INFO)
  end
end

---List all fork remotes
---@return string[] List of fork remote names
function M.list_fork_remotes()
  local git = require("review.integrations.git")

  local result = git.run({ "remote" })
  if result.code ~= 0 then
    return {}
  end

  local remotes = vim.split(result.stdout, "\n")
  local fork_remotes = {}

  for _, remote in ipairs(remotes) do
    if remote:match("^fork%-") then
      table.insert(fork_remotes, remote)
    end
  end

  return fork_remotes
end

-- Cache for mentionable users (refreshed per session)
local mentionable_users_cache = nil

---Fetch users that can be mentioned in the repo
---@return string[] users List of usernames
function M.fetch_mentionable_users()
  -- Return cached if available
  if mentionable_users_cache then
    return mentionable_users_cache
  end

  local git = require("review.integrations.git")
  local repo = git.parse_repo()
  if not repo then
    return {}
  end

  local users = {}
  local seen = {}

  -- Add PR author and reviewers if we have PR context
  local state = require("review.core.state")
  if state.state.pr then
    local author = state.state.pr.author
    if author and not seen[author] then
      table.insert(users, author)
      seen[author] = true
    end
  end

  -- Add comment authors from current session
  for _, comment in ipairs(state.state.comments or {}) do
    local author = comment.author
    if author and type(author) == "string" and not seen[author] then
      table.insert(users, author)
      seen[author] = true
    end
  end

  -- Fetch collaborators (async would be better but sync is simpler for completion)
  local endpoint = string.format("repos/%s/%s/collaborators", repo.owner, repo.repo)
  local data = M.api(endpoint, { jq = ".[].login" })
  if data and type(data) == "string" then
    for login in data:gmatch("[^\n]+") do
      if login ~= "" and not seen[login] then
        table.insert(users, login)
        seen[login] = true
      end
    end
  end

  -- Fetch recent contributors (assignees-like)
  local contributors_endpoint = string.format("repos/%s/%s/contributors?per_page=20", repo.owner, repo.repo)
  local contributors = M.api(contributors_endpoint)
  if contributors and type(contributors) == "table" then
    for _, contrib in ipairs(contributors) do
      local login = contrib.login
      if login and not seen[login] then
        table.insert(users, login)
        seen[login] = true
      end
    end
  end

  -- Cache the result
  mentionable_users_cache = users

  return users
end

---Clear the mentionable users cache
function M.clear_mentionable_cache()
  mentionable_users_cache = nil
end

return M
