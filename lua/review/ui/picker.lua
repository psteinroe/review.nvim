-- PR picker for review.nvim
-- Uses vim.ui.select for PR selection
local M = {}

local utils = require("review.utils")

---@class Review.PickerItem
---@field pr Review.PR The PR data
---@field display string Display string for the picker

---Format a PR for display in picker
---@param pr Review.PR
---@return string
function M.format_pr(pr)
  local parts = {}

  -- PR number and title
  table.insert(parts, string.format("#%d %s", pr.number, pr.title or ""))

  -- Author
  if pr.author then
    table.insert(parts, string.format("(@%s)", pr.author))
  end

  return table.concat(parts, " ")
end

---Format a PR with details for display
---@param pr Review.PR
---@return string
function M.format_pr_detailed(pr)
  local parts = {}

  -- PR number and title
  table.insert(parts, string.format("#%d %s", pr.number, pr.title or ""))

  -- Author
  if pr.author then
    table.insert(parts, string.format("(@%s)", pr.author))
  end

  -- Stats
  local stats = {}
  if pr.additions and pr.additions > 0 then
    table.insert(stats, string.format("+%d", pr.additions))
  end
  if pr.deletions and pr.deletions > 0 then
    table.insert(stats, string.format("-%d", pr.deletions))
  end
  if pr.changed_files and pr.changed_files > 0 then
    table.insert(stats, string.format("%d files", pr.changed_files))
  end

  if #stats > 0 then
    table.insert(parts, "[" .. table.concat(stats, " ") .. "]")
  end

  -- Branch info
  if pr.branch and pr.base then
    table.insert(parts, string.format("(%s -> %s)", pr.branch, pr.base))
  end

  -- Time
  if pr.created_at then
    local time = utils.relative_time(pr.created_at)
    if time then
      table.insert(parts, time)
    end
  end

  return table.concat(parts, " ")
end

---Build picker items from PRs
---@param prs Review.PR[]
---@param detailed? boolean Whether to use detailed format
---@return Review.PickerItem[]
function M.build_items(prs, detailed)
  local items = {}
  local format_fn = detailed and M.format_pr_detailed or M.format_pr

  for _, pr in ipairs(prs) do
    table.insert(items, {
      pr = pr,
      display = format_fn(pr),
    })
  end

  return items
end

---Show picker for PRs
---@param opts {prs: Review.PR[], prompt: string, detailed?: boolean, on_select: fun(pr: Review.PR)}
function M.show(opts)
  if not opts.prs or #opts.prs == 0 then
    vim.notify("No PRs to select from", vim.log.levels.INFO)
    return
  end

  local items = M.build_items(opts.prs, opts.detailed)

  vim.ui.select(items, {
    prompt = opts.prompt or "Select PR:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice and opts.on_select then
      opts.on_select(choice.pr)
    end
  end)
end

---Show PR picker for review requests
---Fetches PRs where current user is requested as reviewer
function M.review_requests()
  local github = require("review.integrations.github")

  -- Check if gh is available
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated", vim.log.levels.ERROR)
    return
  end

  -- Fetch PRs where user is requested reviewer
  local prs = github.fetch_review_requests()

  if #prs == 0 then
    vim.notify("No review requests", vim.log.levels.INFO)
    return
  end

  M.show({
    prs = prs,
    prompt = "Select PR to review:",
    detailed = true,
    on_select = function(pr)
      require("review").open_pr(pr.number)
    end,
  })
end

---Show picker for all open PRs in the repository
function M.open_prs()
  local github = require("review.integrations.github")

  -- Check if gh is available
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated", vim.log.levels.ERROR)
    return
  end

  local prs = github.fetch_open_prs()

  if #prs == 0 then
    vim.notify("No open PRs", vim.log.levels.INFO)
    return
  end

  M.show({
    prs = prs,
    prompt = "Select PR:",
    detailed = true,
    on_select = function(pr)
      require("review").open_pr(pr.number)
    end,
  })
end

---Show picker for PRs authored by current user
function M.my_prs()
  local github = require("review.integrations.github")

  -- Check if gh is available
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated", vim.log.levels.ERROR)
    return
  end

  -- Use gh pr list with author filter
  local result = github.run({
    "pr",
    "list",
    "--json",
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url",
    "--author",
    "@me",
    "--state",
    "open",
  })

  if result.code ~= 0 then
    vim.notify("Failed to fetch your PRs: " .. result.stderr, vim.log.levels.ERROR)
    return
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    vim.notify("Failed to parse PR list", vim.log.levels.ERROR)
    return
  end

  if #data == 0 then
    vim.notify("No open PRs authored by you", vim.log.levels.INFO)
    return
  end

  -- Transform to PR format
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

  M.show({
    prs = prs,
    prompt = "Select your PR:",
    detailed = true,
    on_select = function(pr)
      require("review").open_pr(pr.number)
    end,
  })
end

---Show picker with custom PR search
---@param search string GitHub search query
---@param prompt? string Picker prompt
function M.search(search, prompt)
  local github = require("review.integrations.github")

  -- Check if gh is available
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated", vim.log.levels.ERROR)
    return
  end

  local result = github.run({
    "pr",
    "list",
    "--json",
    "number,title,author,createdAt,headRefName,baseRefName,additions,deletions,changedFiles,state,url",
    "--search",
    search,
  })

  if result.code ~= 0 then
    vim.notify("Failed to search PRs: " .. result.stderr, vim.log.levels.ERROR)
    return
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data then
    vim.notify("Failed to parse PR list", vim.log.levels.ERROR)
    return
  end

  if #data == 0 then
    vim.notify("No PRs found matching search", vim.log.levels.INFO)
    return
  end

  -- Transform to PR format
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

  M.show({
    prs = prs,
    prompt = prompt or "Select PR:",
    detailed = true,
    on_select = function(pr)
      require("review").open_pr(pr.number)
    end,
  })
end

---Prompt user for PR number input
---@param callback fun(number: number)
function M.input_pr_number(callback)
  vim.ui.input({
    prompt = "PR number: ",
  }, function(input)
    if not input or input == "" then
      return
    end

    local pr_number = tonumber(input)
    if not pr_number then
      vim.notify("Invalid PR number", vim.log.levels.ERROR)
      return
    end

    callback(pr_number)
  end)
end

---Show picker allowing choice between different PR listing modes
function M.pick()
  local choices = {
    { label = "Review requests", action = M.review_requests },
    { label = "Open PRs", action = M.open_prs },
    { label = "My PRs", action = M.my_prs },
    { label = "Enter PR number", action = function()
      M.input_pr_number(function(number)
        require("review").open_pr(number)
      end)
    end },
  }

  vim.ui.select(choices, {
    prompt = "Select PR source:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      choice.action()
    end
  end)
end

return M
