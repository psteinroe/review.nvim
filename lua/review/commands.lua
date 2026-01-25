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

  if #parsed == 0 then
    -- :Review - open local diff against HEAD
    M.open_local()
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

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local parsed = vim.split(args, " ", { trimempty = true })

  -- For now, we'll provide a stub implementation
  -- The full AI integration will be in integrations/ai.lua
  if #parsed == 0 then
    -- :ReviewAI - use configured/auto provider
    M.send_to_ai()
  elseif parsed[1] == "pick" then
    -- :ReviewAI pick - show provider picker
    M.pick_ai_provider()
  elseif parsed[1] == "list" then
    -- :ReviewAI list - show available providers
    M.list_ai_providers()
  elseif parsed[1] == "clipboard" then
    -- :ReviewAI clipboard - copy to clipboard
    M.send_to_clipboard()
  else
    -- :ReviewAI <provider> - use specific provider
    M.send_to_ai(parsed[1])
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
    local completions = { "close", "pr", "panel", "refresh", "status", "main", "HEAD~1", "develop" }
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
  local completions = { "pick", "list", "clipboard", "opencode", "claude", "codex", "aider", "avante" }
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

  -- Setup highlights
  highlights.setup()

  -- Get diff
  local diff_output = git.diff(base)
  if not diff_output or diff_output == "" then
    vim.notify("No changes to review against " .. base, vim.log.levels.INFO)
    return
  end

  -- Parse diff
  local files = diff_parser.parse(diff_output)
  if #files == 0 then
    vim.notify("No changed files found", vim.log.levels.INFO)
    return
  end

  -- Reset and setup state
  state.reset()
  state.set_mode("local", { base = base })
  state.set_files(files)
  state.state.active = true

  -- Open layout
  layout.open()

  -- Render file tree
  file_tree.render()

  -- Open first file if available
  if #files > 0 then
    local diff = require("review.ui.diff")
    diff.open_file(files[1].path)
  end

  vim.notify(string.format("Review opened: %d files changed (base: %s)", #files, base), vim.log.levels.INFO)
end

---Open PR review
---@param pr_number number PR number
function M.open_pr(pr_number)
  local state = require("review.core.state")

  -- For now, show a message that GitHub integration is coming
  -- The full implementation will be in integrations/github.lua
  vim.notify(string.format("Opening PR #%d... (GitHub integration not yet implemented)", pr_number), vim.log.levels.INFO)

  -- Placeholder for PR mode
  state.reset()
  state.set_mode("pr", { pr_mode = "remote" })
  state.state.active = true
end

---Open PR picker
function M.pick_pr()
  -- This will use ui/picker.lua when implemented
  vim.notify("PR picker not yet implemented", vim.log.levels.INFO)
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

---Refresh current review
function M.refresh()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  local signs = require("review.ui.signs")
  local virtual_text = require("review.ui.virtual_text")
  local file_tree = require("review.ui.file_tree")

  signs.refresh()
  virtual_text.refresh()
  file_tree.render()

  vim.notify("Review refreshed", vim.log.levels.INFO)
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

  vim.notify(table.concat(status_lines, "\n"), vim.log.levels.INFO)
end

---Add comment at cursor
---@param comment_type "note" | "issue" | "suggestion" | "praise"
function M.add_comment(comment_type)
  local state = require("review.core.state")
  local comments = require("review.core.comments")
  local float = require("review.ui.float")

  local file = state.state.current_file
  if not file then
    vim.notify("No file open", vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]

  float.multiline_input({
    prompt = "Comment (" .. comment_type .. ")",
  }, function(lines)
    if lines and #lines > 0 then
      local body = table.concat(lines, "\n")
      local comment = comments.add(file, line, body, comment_type)
      vim.notify(string.format("Added %s comment at line %d", comment_type, line), vim.log.levels.INFO)
    end
  end)
end

---Send to AI (stub)
---@param provider? string Specific provider to use
function M.send_to_ai(provider)
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  -- AI integration will be in integrations/ai.lua
  if provider then
    vim.notify(string.format("Sending to AI provider: %s (not yet implemented)", provider), vim.log.levels.INFO)
  else
    vim.notify("Sending to AI (not yet implemented)", vim.log.levels.INFO)
  end
end

---Pick AI provider (stub)
function M.pick_ai_provider()
  vim.notify("AI provider picker not yet implemented", vim.log.levels.INFO)
end

---List AI providers (stub)
function M.list_ai_providers()
  local providers = { "opencode", "claude", "codex", "aider", "avante", "clipboard" }
  vim.notify("Available AI providers:\n  " .. table.concat(providers, "\n  "), vim.log.levels.INFO)
end

---Send to clipboard
function M.send_to_clipboard()
  local state = require("review.core.state")

  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.WARN)
    return
  end

  -- Build prompt for clipboard
  local lines = { "# Code Review", "" }

  -- Add file info
  table.insert(lines, "## Changed Files")
  for _, file in ipairs(state.state.files) do
    table.insert(lines, string.format("- %s (%s)", file.path, file.status))
  end
  table.insert(lines, "")

  -- Add pending comments
  local pending = state.get_pending_comments()
  if #pending > 0 then
    table.insert(lines, "## Review Comments")
    for i, comment in ipairs(pending) do
      local location = comment.file and string.format("`%s:%d`", comment.file, comment.line) or ""
      table.insert(lines, string.format("%d. [%s] %s", i, comment.type or "note", location))
      table.insert(lines, string.format("   %s", comment.body))
      table.insert(lines, "")
    end
  end

  local prompt = table.concat(lines, "\n")
  vim.fn.setreg("+", prompt)
  vim.fn.setreg("*", prompt)

  vim.notify("Review copied to clipboard", vim.log.levels.INFO)
end

return M
