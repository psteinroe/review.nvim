-- User commands for review.nvim
local M = {}

---Setup user commands
function M.setup()
  -- Main Review command
  vim.api.nvim_create_user_command("Review", function(opts)
    M.handle_review_command(opts.args)
  end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete_review(arg_lead, cmd_line, cursor_pos)
    end,
    desc = "Open code review interface",
  })


  -- ReviewAI command for AI integration
  vim.api.nvim_create_user_command("ReviewAI", function(opts)
    M.handle_ai_command(opts.args)
  end, {
    nargs = "?",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete_ai(arg_lead, cmd_line, cursor_pos)
    end,
    desc = "Send review to AI provider",
  })

  -- ReviewAICancel command to stop running AI job
  vim.api.nvim_create_user_command("ReviewAICancel", function()
    local ai = require("review.integrations.ai")
    ai.cancel()
  end, {
    desc = "Cancel running AI job",
  })

  -- ReviewAIStatus command to show AI job status
  vim.api.nvim_create_user_command("ReviewAIStatus", function()
    local ai = require("review.integrations.ai")
    local status = ai.get_status()
    if status then
      vim.notify(status, vim.log.levels.INFO)
    else
      vim.notify("No AI job running", vim.log.levels.INFO)
    end
  end, {
    desc = "Show AI job status",
  })

  -- ReviewAIOutput command to show AI output in floating window
  vim.api.nvim_create_user_command("ReviewAIOutput", function()
    local ai = require("review.integrations.ai")
    ai.show_output()
  end, {
    desc = "Show AI job output",
  })

  -- ReviewAIDebug command to show debug info
  vim.api.nvim_create_user_command("ReviewAIDebug", function()
    local ai = require("review.integrations.ai")
    local info = ai.get_debug_info()
    vim.notify(info, vim.log.levels.INFO)
  end, {
    desc = "Show AI job debug info",
  })

  -- ReviewAICopyCmd command to copy command for manual testing
  vim.api.nvim_create_user_command("ReviewAICopyCmd", function()
    local ai = require("review.integrations.ai")
    ai.copy_command()
  end, {
    desc = "Copy AI command to clipboard for manual testing",
  })

  -- ReviewComment command for quick comment actions
  vim.api.nvim_create_user_command("ReviewComment", function(opts)
    M.handle_comment_command(opts.args)
  end, {
    nargs = "?",
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.complete_comment(arg_lead, cmd_line, cursor_pos)
    end,
    desc = "Add review comment at cursor",
  })
end

---Handle :Review command
---@param args string Command arguments
function M.handle_review_command(args)
  local parsed = vim.split(args, " ", { trimempty = true })

  if #parsed == 0 or parsed[1] == "open" then
    -- :Review or :Review open - auto-detect PR → hybrid mode; else local mode
    local github = require("review.integrations.github")
    if github.is_available() then
      local pr_number = github.get_current_pr_number()
      if pr_number then
        M.open_hybrid(pr_number)
        return
      end
    end
    M.open_local()
  elseif parsed[1] == "local" then
    -- :Review local - force local mode (ignore PR)
    M.open_local(parsed[2])
  elseif parsed[1] == "close" then
    -- :Review close
    M.close()
  elseif parsed[1] == "pr" then
    if parsed[2] then
      -- :Review pr 123
      local pr_number = tonumber(parsed[2])
      if pr_number then
        M.open_pr(pr_number)
      else
        vim.notify("Invalid PR number: " .. parsed[2], vim.log.levels.ERROR)
      end
    else
      -- :Review pr - open picker
      M.pick_pr()
    end
  elseif parsed[1] == "panel" then
    -- :Review panel - toggle PR panel
    M.toggle_panel()
  elseif parsed[1] == "next" then
    -- :Review next - open next unreviewed PR
    M.open_next_pr()
  elseif parsed[1] == "refresh" then
    -- :Review refresh - refresh current review
    M.refresh()
  elseif parsed[1] == "status" then
    -- :Review status - show review status
    M.show_status()
  else
    -- :Review {base} - diff against branch/commit
    M.open_local(parsed[1])
  end
end

---Handle :ReviewAI command
---@param args string Command arguments
function M.handle_ai_command(args)
  local state = require("review.core.state")
  local ai = require("review.integrations.ai")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local parsed = vim.split(args, " ", { trimempty = true })

  if #parsed == 0 then
    -- :ReviewAI - prompt for extra instructions, then send
    ai.send_with_prompt()
  elseif parsed[1] == "pick" then
    -- :ReviewAI pick - show provider picker
    ai.pick_provider()
  elseif parsed[1] == "list" then
    -- :ReviewAI list - show available providers
    M.list_ai_providers()
  elseif parsed[1] == "clipboard" then
    -- :ReviewAI clipboard - copy to clipboard
    ai.send_to_clipboard()
  elseif parsed[1] == "status" then
    -- :ReviewAI status - show status
    local status = ai.get_status()
    if status then
      vim.notify(status, vim.log.levels.INFO)
    else
      vim.notify("No AI job running", vim.log.levels.INFO)
    end
  elseif parsed[1] == "cancel" then
    -- :ReviewAI cancel - cancel job
    ai.cancel()
  else
    -- :ReviewAI <provider> - use specific provider (not implemented for background mode)
    vim.notify("Use :ReviewAI pick to select a provider", vim.log.levels.INFO)
  end
end

---Handle :ReviewComment command
---@param args string Command arguments
function M.handle_comment_command(args)
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local parsed = vim.split(args, " ", { trimempty = true })
  local comment_type = parsed[1] or "note"

  -- Validate comment type
  local valid_types = { "note", "issue", "suggestion", "praise" }
  if not vim.tbl_contains(valid_types, comment_type) then
    vim.notify("Invalid comment type: " .. comment_type .. ". Use: " .. table.concat(valid_types, ", "), vim.log.levels.ERROR)
    return
  end

  M.add_comment(comment_type)
end

---Complete :Review command
---@param arg_lead string Current argument being typed
---@param cmd_line string Full command line
---@param cursor_pos number Cursor position
---@return string[]
function M.complete_review(arg_lead, cmd_line, cursor_pos)
  local args = vim.split(cmd_line, " ", { trimempty = true })

  -- First argument completions
  if #args <= 2 then
    local completions = { "close", "local", "next", "pr", "panel", "refresh", "status", "main", "HEAD~1", "develop" }
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) == 1
    end, completions)
  end

  -- PR number completion - we could fetch PR numbers here
  if #args == 3 and args[2] == "pr" then
    -- Could return list of open PR numbers
    return {}
  end

  return {}
end

---Complete :ReviewAI command
---@param arg_lead string Current argument being typed
---@param cmd_line string Full command line
---@param cursor_pos number Cursor position
---@return string[]
function M.complete_ai(arg_lead, cmd_line, cursor_pos)
  local completions = { "pick", "list", "clipboard", "status", "cancel" }
  return vim.tbl_filter(function(item)
    return item:find(arg_lead, 1, true) == 1
  end, completions)
end

---Complete :ReviewComment command
---@param arg_lead string Current argument being typed
---@param cmd_line string Full command line
---@param cursor_pos number Cursor position
---@return string[]
function M.complete_comment(arg_lead, cmd_line, cursor_pos)
  local completions = { "note", "issue", "suggestion", "praise" }
  return vim.tbl_filter(function(item)
    return item:find(arg_lead, 1, true) == 1
  end, completions)
end

-- =============================================================================
-- Command Implementations
-- =============================================================================

---Open local diff review
---@param base? string Base ref to diff against (default: HEAD)
function M.open_local(base)
  base = base or "HEAD"

  local state = require("review.core.state")
  local git = require("review.integrations.git")
  local diff_parser = require("review.core.diff_parser")
  local layout = require("review.ui.layout")
  local file_tree = require("review.ui.file_tree")
  local highlights = require("review.ui.highlights")
  local signs = require("review.ui.signs")

  -- Setup highlights and signs
  highlights.setup()
  signs.setup()

  -- Get diff for tracked changes
  local diff_output = git.diff(base)

  -- Parse diff
  local files = diff_parser.parse(diff_output or "")

  -- Also include untracked files as "added"
  local untracked = git.get_untracked_files()
  local seen = {}
  for _, f in ipairs(files) do
    seen[f.path] = true
  end
  for _, path in ipairs(untracked) do
    if not seen[path] then
      table.insert(files, {
        path = path,
        status = "added",
        additions = 0,
        deletions = 0,
        comment_count = 0,
        hunks = {},
        reviewed = false,
      })
    end
  end

  if #files == 0 then
    vim.notify("No changes to review against " .. base, vim.log.levels.INFO)
    return
  end

  -- Reset and setup state
  state.reset()
  state.set_mode("local", { base = base })
  state.set_files(files)
  state.state.active = true

  -- Load stored comments
  local stored_comments = state.load_stored()
  if #stored_comments > 0 then
    for _, comment in ipairs(stored_comments) do
      table.insert(state.state.comments, comment)
    end
    state.update_file_comment_counts()
    vim.notify(string.format("Loaded %d stored comments", #stored_comments), vim.log.levels.INFO)
  end

  -- Open layout
  layout.open()

  -- Initialize file tree (sets up keymaps and renders)
  file_tree.init()

  -- Open first file automatically
  file_tree.open_selected()

  vim.notify(string.format("Review opened: %d files changed (base: %s)", #files, base), vim.log.levels.INFO)
end

---Open hybrid review (PR metadata + local diff with provenance)
---@param pr_number number PR number
function M.open_hybrid(pr_number)
  local state = require("review.core.state")
  local github = require("review.integrations.github")
  local git = require("review.integrations.git")
  local diff_parser = require("review.core.diff_parser")
  local layout = require("review.ui.layout")
  local file_tree = require("review.ui.file_tree")
  local highlights = require("review.ui.highlights")
  local signs = require("review.ui.signs")

  -- Check gh availability
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available. Falling back to local mode.", vim.log.levels.WARN)
    M.open_local()
    return
  end

  vim.notify(string.format("Opening hybrid review for PR #%d...", pr_number), vim.log.levels.INFO)

  -- Fetch origin to ensure we have latest remote refs
  vim.notify("Fetching from origin...", vim.log.levels.INFO)
  local fetch_ok = git.fetch()
  if not fetch_ok then
    vim.notify("Warning: git fetch failed. Provenance may be inaccurate.", vim.log.levels.WARN)
  end

  -- Fetch PR details
  local pr = github.fetch_pr(pr_number)
  if not pr then
    vim.notify(
      string.format("Could not fetch PR #%d details. Falling back to local mode.", pr_number),
      vim.log.levels.WARN
    )
    M.open_local()
    return
  end

  -- Check if PR is still open
  if pr.state ~= "open" then
    vim.notify(string.format("PR #%d is %s. Opening in local mode.", pr_number, pr.state), vim.log.levels.WARN)
    M.open_local("origin/" .. pr.base)
    return
  end

  -- Determine base and origin_head refs
  local base_ref = "origin/" .. pr.base
  local origin_head = git.get_tracking_branch()

  -- If no tracking branch, fall back to origin/{branch}
  if not origin_head then
    origin_head = "origin/" .. pr.branch
    -- Check if this ref exists
    if not git.ref_exists(origin_head) then
      vim.notify("No remote tracking branch found. Falling back to local mode.", vim.log.levels.WARN)
      M.open_local(base_ref)
      return
    end
  end

  -- Find merge-base to only show PR's changes, not unrelated changes on base branch
  local merge_base = git.merge_base(base_ref, "HEAD")
  local diff_base = merge_base or base_ref
  if not merge_base then
    vim.notify("Could not find merge-base, using " .. base_ref, vim.log.levels.WARN)
  end

  -- Get diff for all local changes vs merge-base (includes pushed, local commits, and uncommitted)
  local diff_output = git.diff(diff_base)

  -- Parse diff
  local files = diff_parser.parse(diff_output or "")

  -- Also include untracked files as "added"
  local untracked = git.get_untracked_files()
  local seen = {}
  for _, f in ipairs(files) do
    seen[f.path] = true
  end
  for _, path in ipairs(untracked) do
    if not seen[path] then
      table.insert(files, {
        path = path,
        status = "added",
        additions = 0,
        deletions = 0,
        comment_count = 0,
        hunks = {},
        reviewed = false,
      })
    end
  end

  if #files == 0 then
    vim.notify("No changes to review against " .. diff_base, vim.log.levels.INFO)
    return
  end

  -- Compute provenance for each file
  git.compute_provenance(files, base_ref, origin_head)

  -- Setup highlights and signs
  highlights.setup()
  signs.setup()

  -- Reset and setup state
  state.reset()
  state.set_mode("hybrid", {
    base = base_ref,
    diff_base = diff_base, -- merge-base for actual diff
    pr = pr,
    origin_head = origin_head,
  })
  state.set_files(files)
  state.state.active = true

  -- Fetch existing comments from GitHub
  local comments = github.fetch_all_comments(pr_number)
  for _, comment in ipairs(comments) do
    -- Only add code comments (ones with file/line info)
    if comment.file and comment.line then
      table.insert(state.state.comments, comment)
    end
  end

  -- Load stored local comments (only pending ones)
  local stored_comments = state.load_stored()
  local pending_count = 0
  for _, comment in ipairs(stored_comments) do
    if comment.status ~= "submitted" then
      table.insert(state.state.comments, comment)
      pending_count = pending_count + 1
    end
  end
  if pending_count > 0 then
    vim.notify(string.format("Loaded %d pending comments", pending_count), vim.log.levels.INFO)
  end

  -- Update file comment counts
  github.update_file_comment_counts()

  -- Open layout
  layout.open()

  -- Initialize file tree
  file_tree.init()

  -- Open first file automatically
  file_tree.open_selected()

  -- Get provenance stats for notification
  local prov_stats = state.get_provenance_stats()
  local stats_parts = {}
  if prov_stats.pushed > 0 then
    table.insert(stats_parts, string.format("%d pushed", prov_stats.pushed))
  end
  if prov_stats.local_commits > 0 then
    table.insert(stats_parts, string.format("%d local", prov_stats.local_commits))
  end
  if prov_stats.uncommitted > 0 then
    table.insert(stats_parts, string.format("%d uncommitted", prov_stats.uncommitted))
  end

  local stats_str = #stats_parts > 0 and (" (" .. table.concat(stats_parts, ", ") .. ")") or ""
  vim.notify(
    string.format("Hybrid review: PR #%d • %d files%s", pr.number, #files, stats_str),
    vim.log.levels.INFO
  )
end

---Open PR review
---@param pr_number number PR number
function M.open_pr(pr_number)
  local state = require("review.core.state")
  local github = require("review.integrations.github")
  local git = require("review.integrations.git")
  local diff_parser = require("review.core.diff_parser")
  local layout = require("review.ui.layout")
  local file_tree = require("review.ui.file_tree")
  local highlights = require("review.ui.highlights")
  local signs = require("review.ui.signs")

  -- Check gh availability
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated. Run: gh auth login", vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Fetching PR #%d...", pr_number), vim.log.levels.INFO)

  -- Fetch PR details
  local pr = github.fetch_pr(pr_number)
  if not pr then
    vim.notify(string.format("Failed to fetch PR #%d", pr_number), vim.log.levels.ERROR)
    return
  end

  -- Check if we're on the PR branch (local mode) or need remote mode
  local current_branch = git.current_branch()
  local is_on_pr_branch = current_branch == pr.branch

  -- Determine pr_mode
  local pr_mode = is_on_pr_branch and "local" or "remote"

  -- For remote mode, fetch the PR branch so we can view its content
  if pr_mode == "remote" then
    vim.notify("Fetching PR branch...", vim.log.levels.INFO)
    -- Fetch the PR ref using gh
    local fetch_result = github.run({ "pr", "checkout", tostring(pr_number), "--detach" })
    if fetch_result.code ~= 0 then
      -- Try fetching via git
      git.run({ "fetch", "origin", pr.branch })
    end
    -- Go back to original branch
    if current_branch then
      git.run({ "checkout", current_branch })
    end
  end

  -- Fetch PR diff
  local diff_output = github.fetch_pr_diff(pr_number)
  if not diff_output or diff_output == "" then
    vim.notify("Failed to fetch PR diff", vim.log.levels.ERROR)
    return
  end

  -- Parse diff into files
  local files = diff_parser.parse(diff_output)
  if #files == 0 then
    vim.notify("No files changed in PR", vim.log.levels.INFO)
    return
  end

  -- Setup highlights and signs
  highlights.setup()
  signs.setup()

  -- Reset and setup state
  state.reset()
  state.set_mode("pr", { pr_mode = pr_mode })
  state.state.pr = pr
  state.state.base = "origin/" .. pr.base
  -- For remote, use origin/branch; for local, use working tree
  state.state.pr_head_ref = pr_mode == "remote" and ("origin/" .. pr.branch) or nil
  state.set_files(files)
  state.state.active = true

  -- Fetch existing comments from GitHub
  local comments = github.fetch_all_comments(pr_number)
  for _, comment in ipairs(comments) do
    -- Only add code comments (ones with file/line info)
    if comment.file and comment.line then
      table.insert(state.state.comments, comment)
    end
  end

  -- Load stored local comments (only pending ones - submitted are now on GitHub)
  local stored_comments = state.load_stored()
  local pending_count = 0
  for _, comment in ipairs(stored_comments) do
    -- Skip submitted comments - they're already fetched from GitHub above
    if comment.status ~= "submitted" then
      table.insert(state.state.comments, comment)
      pending_count = pending_count + 1
    end
  end
  if pending_count > 0 then
    vim.notify(string.format("Loaded %d pending comments", pending_count), vim.log.levels.INFO)
  end

  -- Update file comment counts
  github.update_file_comment_counts()

  -- Open layout
  layout.open()

  -- Initialize file tree
  file_tree.init()

  -- Open first file automatically
  file_tree.open_selected()

  local mode_str = pr_mode == "local" and " (local)" or ""
  vim.notify(string.format("PR #%d: %s (%d files)%s", pr.number, pr.title, #files, mode_str), vim.log.levels.INFO)
end

---Open PR picker
function M.pick_pr()
  local github = require("review.integrations.github")
  local picker = require("review.ui.picker")

  -- Check gh availability
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated. Run: gh auth login", vim.log.levels.ERROR)
    return
  end

  -- Show picker with options
  picker.pick()
end

---Open next unreviewed PR from review requests
function M.open_next_pr()
  local github = require("review.integrations.github")
  local state = require("review.core.state")

  -- Check gh availability
  if not github.is_available() then
    vim.notify("GitHub CLI (gh) not available or not authenticated. Run: gh auth login", vim.log.levels.ERROR)
    return
  end

  -- Get current PR number to exclude
  local current_pr = state.state.pr and state.state.pr.number or nil

  -- Close current review if active
  if state.is_active() then
    local layout = require("review.ui.layout")
    layout.close()
  end

  -- Fetch next unreviewed PR
  local next_pr = github.fetch_next_unreviewed_pr(current_pr)
  if not next_pr then
    vim.notify("No more unreviewed PRs in your review requests", vim.log.levels.INFO)
    return
  end

  -- Open the next PR
  vim.notify(string.format("Opening PR #%d: %s", next_pr.number, next_pr.title or ""), vim.log.levels.INFO)
  M.open_pr(next_pr.number)
end

---Close review session
function M.close()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.INFO)
    return
  end

  local layout = require("review.ui.layout")
  layout.close()

  vim.notify("Review closed", vim.log.levels.INFO)
end

---Toggle PR panel
function M.toggle_panel()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  -- Panel will be implemented in ui/panel.lua
  vim.notify("Panel toggle not yet implemented", vim.log.levels.INFO)
end

---Refresh current review (re-fetch git state and PR data)
function M.refresh()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local git = require("review.integrations.git")
  local diff_parser = require("review.core.diff_parser")
  local file_tree = require("review.ui.file_tree")
  local signs = require("review.ui.signs")
  local virtual_text = require("review.ui.virtual_text")

  local mode = state.state.mode
  local base = state.state.base
  local pr = state.state.pr
  local origin_head = state.state.origin_head

  vim.notify("Refreshing review...", vim.log.levels.INFO)

  -- For hybrid/pr modes, fetch from origin first
  if mode == "hybrid" or mode == "pr" then
    local github = require("review.integrations.github")
    git.fetch()

    -- Re-fetch PR to check if it's still open
    if pr then
      local updated_pr = github.fetch_pr(pr.number)
      if updated_pr then
        state.state.pr = updated_pr
        pr = updated_pr
      end
    end
  end

  -- Re-compute diff
  local diff_output = git.diff(base)
  local files = diff_parser.parse(diff_output or "")

  -- Include untracked files
  local untracked = git.get_untracked_files()
  local seen = {}
  for _, f in ipairs(files) do
    seen[f.path] = true
  end
  for _, path in ipairs(untracked) do
    if not seen[path] then
      table.insert(files, {
        path = path,
        status = "added",
        additions = 0,
        deletions = 0,
        comment_count = 0,
        hunks = {},
        reviewed = false,
      })
    end
  end

  -- Preserve reviewed status from old files
  local old_reviewed = {}
  for _, f in ipairs(state.state.files) do
    old_reviewed[f.path] = f.reviewed
  end
  for _, f in ipairs(files) do
    if old_reviewed[f.path] then
      f.reviewed = true
    end
  end

  -- Re-compute provenance for hybrid mode
  if mode == "hybrid" and origin_head then
    git.compute_provenance(files, base, origin_head)
  end

  -- Update state with new files
  state.set_files(files)

  -- Re-fetch comments for hybrid/pr modes
  if (mode == "hybrid" or mode == "pr") and pr then
    local github = require("review.integrations.github")
    -- Keep local pending comments, refresh GitHub comments
    local local_comments = {}
    for _, c in ipairs(state.state.comments) do
      if c.kind == "local" and c.status == "pending" then
        table.insert(local_comments, c)
      end
    end

    -- Clear and re-add
    state.state.comments = {}
    local gh_comments = github.fetch_all_comments(pr.number)
    for _, comment in ipairs(gh_comments) do
      if comment.file and comment.line then
        table.insert(state.state.comments, comment)
      end
    end
    for _, comment in ipairs(local_comments) do
      table.insert(state.state.comments, comment)
    end

    github.update_file_comment_counts()
  end

  -- Refresh UI
  file_tree.render()
  signs.refresh()
  virtual_text.refresh()

  -- Show status
  if #files == 0 then
    vim.notify("Refresh complete: No changes found", vim.log.levels.INFO)
  else
    local msg = string.format("Refresh complete: %d files", #files)
    if mode == "hybrid" then
      local prov_stats = state.get_provenance_stats()
      local parts = {}
      if prov_stats.pushed > 0 then
        table.insert(parts, string.format("%d pushed", prov_stats.pushed))
      end
      if prov_stats.local_commits > 0 then
        table.insert(parts, string.format("%d local", prov_stats.local_commits))
      end
      if prov_stats.uncommitted > 0 then
        table.insert(parts, string.format("%d uncommitted", prov_stats.uncommitted))
      end
      if #parts > 0 then
        msg = msg .. " (" .. table.concat(parts, ", ") .. ")"
      end
    end
    vim.notify(msg, vim.log.levels.INFO)
  end
end

---Show review status
function M.show_status()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.INFO)
    return
  end

  local stats = state.get_stats()
  local mode = state.state.mode
  local base = state.state.base

  local status_lines = {
    "Review Status:",
    string.format("  Mode: %s", mode),
    string.format("  Base: %s", base),
    string.format("  Files: %d", stats.total_files),
    string.format("  Comments: %d", stats.total_comments),
    string.format("  Pending: %d", stats.pending_comments),
    string.format("  Unresolved: %d", stats.unresolved_comments),
  }

  if state.state.pr then
    table.insert(status_lines, 3, string.format("  PR: #%d - %s", state.state.pr.number, state.state.pr.title))
  end

  -- Show provenance stats for hybrid mode
  if mode == "hybrid" then
    local prov_stats = state.get_provenance_stats()
    table.insert(status_lines, string.format("  Provenance:"))
    table.insert(status_lines, string.format("    Pushed: %d", prov_stats.pushed))
    table.insert(status_lines, string.format("    Local: %d", prov_stats.local_commits))
    table.insert(status_lines, string.format("    Uncommitted: %d", prov_stats.uncommitted))
    if prov_stats.both > 0 then
      table.insert(status_lines, string.format("    Both: %d", prov_stats.both))
    end
  end

  vim.notify(table.concat(status_lines, "\n"), vim.log.levels.INFO)
end

---Add comment at cursor
---@param comment_type "note" | "issue" | "suggestion" | "praise"
function M.add_comment(comment_type)
  local state = require("review.core.state")
  local comments = require("review.core.comments")
  local float = require("review.ui.float")
  local signs = require("review.ui.signs")
  local virtual_text = require("review.ui.virtual_text")
  local file_tree = require("review.ui.file_tree")

  local file = state.state.current_file
  if not file then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local original_win = vim.api.nvim_get_current_win()

  float.multiline_input({
    prompt = string.format("Comment (%s)", comment_type),
    file = file,
    line = line,
    filetype = "markdown",
  }, function(lines)
    if lines and #lines > 0 then
      local body = table.concat(lines, "\n")
      comments.add(file, line, body, comment_type)
      vim.schedule(function()
        signs.refresh()
        virtual_text.refresh()
        file_tree.render()
        -- Restore cursor to comment line
        if vim.api.nvim_win_is_valid(original_win) then
          vim.api.nvim_set_current_win(original_win)
          pcall(vim.api.nvim_win_set_cursor, original_win, { line, 0 })
        end
        vim.notify(string.format("Added %s comment at line %d", comment_type, line), vim.log.levels.INFO)
      end)
    end
  end)
end

---Send to AI
function M.send_to_ai()
  local state = require("review.core.state")
  local ai = require("review.integrations.ai")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  ai.send_with_prompt()
end

---Pick AI provider
function M.pick_ai_provider()
  local ai = require("review.integrations.ai")
  ai.pick_provider()
end

---List AI providers
function M.list_ai_providers()
  local ai = require("review.integrations.ai")
  local providers = ai.get_available_providers()

  local lines = { "Available AI providers:" }
  for _, p in ipairs(providers) do
    local status = p.available and "✓" or "✗"
    table.insert(lines, string.format("  %s %s", status, p.name))
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---Send to clipboard
function M.send_to_clipboard()
  local state = require("review.core.state")
  local ai = require("review.integrations.ai")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  ai.send_to_clipboard()
end

return M
