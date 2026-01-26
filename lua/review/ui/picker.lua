-- PR picker for review.nvim
-- Supports multiple picker backends: native (vim.ui.select), Telescope, fzf-lua
local M = {}

local utils = require("review.utils")

---@alias Review.PickerBackend "native" | "telescope" | "fzf-lua" | "auto"

---@type Review.PickerBackend
M.backend = "auto"

---Check if Telescope is available
---@return boolean
local function has_telescope()
  local ok = pcall(require, "telescope")
  return ok
end

---Check if fzf-lua is available
---@return boolean
local function has_fzf_lua()
  local ok = pcall(require, "fzf-lua")
  return ok
end

---Detect best available picker
---@return Review.PickerBackend
local function detect_backend()
  -- Check config preference first
  local config = require("review.config")
  local preferred = config.get("picker.backend")
  if preferred and preferred ~= "auto" then
    -- Validate the preference
    if preferred == "telescope" and has_telescope() then
      return "telescope"
    elseif preferred == "fzf-lua" and has_fzf_lua() then
      return "fzf-lua"
    elseif preferred == "native" then
      return "native"
    end
  end

  -- Auto-detect: prefer Telescope, then fzf-lua, then native
  if has_telescope() then
    return "telescope"
  elseif has_fzf_lua() then
    return "fzf-lua"
  else
    return "native"
  end
end

---Get the active backend
---@return Review.PickerBackend
function M.get_backend()
  if M.backend == "auto" then
    return detect_backend()
  end
  return M.backend
end

---Set the picker backend
---@param backend Review.PickerBackend
function M.set_backend(backend)
  M.backend = backend
end

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

---Show picker using native vim.ui.select
---@param opts {prs: Review.PR[], prompt: string, detailed?: boolean, on_select: fun(pr: Review.PR)}
local function show_native(opts)
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

---Show picker using Telescope
---@param opts {prs: Review.PR[], prompt: string, detailed?: boolean, on_select: fun(pr: Review.PR)}
local function show_telescope(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local items = M.build_items(opts.prs, opts.detailed)

  pickers
    .new({}, {
      prompt_title = opts.prompt or "Select PR",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return {
            value = item,
            display = item.display,
            ordinal = item.display,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and opts.on_select then
            opts.on_select(selection.value.pr)
          end
        end)
        return true
      end,
    })
    :find()
end

---Show picker using fzf-lua
---@param opts {prs: Review.PR[], prompt: string, detailed?: boolean, on_select: fun(pr: Review.PR)}
local function show_fzf_lua(opts)
  local fzf = require("fzf-lua")

  local items = M.build_items(opts.prs, opts.detailed)

  -- Build display strings and lookup table
  local entries = {}
  local lookup = {}
  for _, item in ipairs(items) do
    table.insert(entries, item.display)
    lookup[item.display] = item.pr
  end

  fzf.fzf_exec(entries, {
    prompt = (opts.prompt or "Select PR") .. "> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] and opts.on_select then
          local pr = lookup[selected[1]]
          if pr then
            opts.on_select(pr)
          end
        end
      end,
    },
    winopts = {
      height = 0.6,
      width = 0.8,
    },
  })
end

---Show picker for PRs
---@param opts {prs: Review.PR[], prompt: string, detailed?: boolean, on_select: fun(pr: Review.PR)}
function M.show(opts)
  if not opts.prs or #opts.prs == 0 then
    vim.notify("No PRs to select from", vim.log.levels.INFO)
    return
  end

  local backend = M.get_backend()

  if backend == "telescope" and has_telescope() then
    show_telescope(opts)
  elseif backend == "fzf-lua" and has_fzf_lua() then
    show_fzf_lua(opts)
  else
    show_native(opts)
  end
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

---Pick a file from the review file list using fuzzy finder
---@param opts? {on_select?: fun(file: Review.File)}
function M.pick_file(opts)
  opts = opts or {}
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local files = state.state.files
  if #files == 0 then
    vim.notify("No files in review", vim.log.levels.INFO)
    return
  end

  -- Build items for picker
  local items = {}
  for _, file in ipairs(files) do
    local status_icons = {
      added = "A",
      modified = "M",
      deleted = "D",
      renamed = "R",
    }
    local status = status_icons[file.status] or "?"
    local reviewed = file.reviewed and "✓" or "·"
    local comment_count, has_pending = state.get_file_comment_info(file.path)
    local comments = ""
    if comment_count > 0 then
      comments = string.format(" [%d%s]", comment_count, has_pending and "*" or "")
    end

    table.insert(items, {
      file = file,
      display = string.format("%s %s %s%s", reviewed, status, file.path, comments),
    })
  end

  local backend = M.get_backend()

  if backend == "telescope" and has_telescope() then
    M.pick_file_telescope(items, opts)
  elseif backend == "fzf-lua" and has_fzf_lua() then
    M.pick_file_fzf_lua(items, opts)
  else
    M.pick_file_native(items, opts)
  end
end

---Pick file using telescope
---@param items table[]
---@param opts {on_select?: fun(file: Review.File)}
function M.pick_file_telescope(items, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Review Files",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return {
            value = item,
            display = item.display,
            ordinal = item.file.path, -- Match on path for fuzzy finding
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            local file = selection.value.file
            if opts.on_select then
              opts.on_select(file)
            else
              -- Default: open file in diff view
              local file_tree = require("review.ui.file_tree")
              local diff = require("review.ui.diff")
              file_tree.select_by_path(file.path)
              diff.open_file(file.path)
              file_tree.render()
            end
          end
        end)
        return true
      end,
    })
    :find()
end

---Pick file using fzf-lua
---@param items table[]
---@param opts {on_select?: fun(file: Review.File)}
function M.pick_file_fzf_lua(items, opts)
  local fzf = require("fzf-lua")

  local entries = {}
  local lookup = {}
  for _, item in ipairs(items) do
    table.insert(entries, item.display)
    lookup[item.display] = item.file
  end

  fzf.fzf_exec(entries, {
    prompt = "Review Files> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          local file = lookup[selected[1]]
          if file then
            if opts.on_select then
              opts.on_select(file)
            else
              local file_tree = require("review.ui.file_tree")
              local diff = require("review.ui.diff")
              file_tree.select_by_path(file.path)
              diff.open_file(file.path)
              file_tree.render()
            end
          end
        end
      end,
    },
    winopts = {
      height = 0.6,
      width = 0.8,
    },
  })
end

---Pick file using native vim.ui.select
---@param items table[]
---@param opts {on_select?: fun(file: Review.File)}
function M.pick_file_native(items, opts)
  vim.ui.select(items, {
    prompt = "Select file:",
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if choice then
      if opts.on_select then
        opts.on_select(choice.file)
      else
        local file_tree = require("review.ui.file_tree")
        local diff = require("review.ui.diff")
        file_tree.select_by_path(choice.file.path)
        diff.open_file(choice.file.path)
        file_tree.render()
      end
    end
  end)
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
