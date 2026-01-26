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
    -- :Review or :Review open - open local diff against HEAD
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

  -- Open layout
  layout.open()

  -- Initialize file tree (sets up keymaps and renders)
  file_tree.init()

  -- Focus on file tree with first file selected (don't auto-open diff)
  layout.focus_tree()

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
