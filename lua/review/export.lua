-- Export module for review.nvim
-- Generates markdown and other formats for sharing review comments
local M = {}

local state = require("review.core.state")
local utils = require("review.utils")

---@class Review.ExportOptions
---@field include_diff? boolean Include diff in export (default: true)
---@field include_comments? boolean Include comments (default: true)
---@field include_pr_info? boolean Include PR metadata (default: true)
---@field include_instructions? boolean Include AI instructions (default: true)
---@field context_lines? number Lines of context around comments (default: 3)
---@field format? "markdown" | "json" | "plain" Export format (default: "markdown")
---@field comment_types? string[] Filter by comment types (default: all)
---@field only_pending? boolean Only include pending comments (default: false)

---Get comment type label for display
---@param comment Review.Comment
---@return string
local function get_type_label(comment)
  if comment.type then
    return string.upper(comment.type)
  end
  if comment.kind == "local" then
    return "NOTE"
  end
  return "COMMENT"
end

---Format a single comment for markdown export
---@param comment Review.Comment
---@param index number Comment index
---@return string
local function format_comment_markdown(comment, index)
  local parts = {}

  local type_label = get_type_label(comment)
  local location = ""

  if comment.file then
    if comment.line then
      location = string.format("`%s:%d`", comment.file, comment.line)
    else
      location = string.format("`%s`", comment.file)
    end
  end

  if location ~= "" then
    table.insert(parts, string.format("%d. **[%s]** %s - %s", index, type_label, location, comment.body))
  else
    table.insert(parts, string.format("%d. **[%s]** %s", index, type_label, comment.body))
  end

  return table.concat(parts, "\n")
end

---Generate markdown export
---@param opts? Review.ExportOptions
---@return string markdown
function M.generate_markdown(opts)
  opts = vim.tbl_extend("force", {
    include_diff = true,
    include_comments = true,
    include_pr_info = true,
    include_instructions = true,
    context_lines = 3,
    format = "markdown",
    only_pending = false,
  }, opts or {})

  local lines = {}

  -- Header based on mode
  if state.state.mode == "pr" and state.state.pr and opts.include_pr_info then
    local pr = state.state.pr
    table.insert(lines, string.format("# PR #%d: %s", pr.number, pr.title))
    table.insert(lines, "")
    table.insert(lines, string.format("**Author:** @%s", pr.author))
    table.insert(lines, string.format("**Branch:** %s -> %s", pr.branch, pr.base))
    table.insert(lines, string.format("**Changes:** +%d -%d (%d files)", pr.additions, pr.deletions, pr.changed_files))

    if pr.description and pr.description ~= "" then
      table.insert(lines, "")
      table.insert(lines, "## Description")
      table.insert(lines, "")
      table.insert(lines, pr.description)
    end

    table.insert(lines, "")
  else
    table.insert(lines, "# Code Review")
    table.insert(lines, "")
  end

  -- Instructions for AI
  if opts.include_instructions then
    table.insert(lines, "---")
    table.insert(lines, "")
    table.insert(lines, "I reviewed your code and have the following comments. Please address them.")
    table.insert(lines, "")
    table.insert(
      lines,
      "Comment types: **ISSUE** (problems to fix), **SUGGESTION** (improvements), **NOTE** (observations), **PRAISE** (positive feedback)"
    )
    table.insert(lines, "")
  end

  -- Comments section
  if opts.include_comments then
    local comments = state.state.comments

    -- Filter by pending if requested
    if opts.only_pending then
      comments = vim.tbl_filter(function(c)
        return c.kind == "local" and c.status == "pending"
      end, comments)
    end

    -- Filter by type if specified
    if opts.comment_types then
      comments = vim.tbl_filter(function(c)
        return vim.tbl_contains(opts.comment_types, c.type or "note")
      end, comments)
    end

    -- Sort by file and line
    table.sort(comments, function(a, b)
      if (a.file or "") ~= (b.file or "") then
        return (a.file or "") < (b.file or "")
      end
      return (a.line or 0) < (b.line or 0)
    end)

    if #comments > 0 then
      table.insert(lines, "## Review Comments")
      table.insert(lines, "")

      for i, comment in ipairs(comments) do
        table.insert(lines, format_comment_markdown(comment, i))
      end

      table.insert(lines, "")
    else
      table.insert(lines, "No comments yet.")
      table.insert(lines, "")
    end
  end

  -- Diff section
  if opts.include_diff then
    local diff = M.get_diff()
    if diff and diff ~= "" then
      table.insert(lines, "## Diff")
      table.insert(lines, "")
      table.insert(lines, "```diff")
      table.insert(lines, diff)
      table.insert(lines, "```")
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

---Generate plain text export
---@param opts? Review.ExportOptions
---@return string
function M.generate_plain(opts)
  opts = opts or {}

  local lines = {}

  local comments = state.state.comments

  if opts.only_pending then
    comments = vim.tbl_filter(function(c)
      return c.kind == "local" and c.status == "pending"
    end, comments)
  end

  -- Sort by file and line
  table.sort(comments, function(a, b)
    if (a.file or "") ~= (b.file or "") then
      return (a.file or "") < (b.file or "")
    end
    return (a.line or 0) < (b.line or 0)
  end)

  for i, comment in ipairs(comments) do
    local type_label = get_type_label(comment)
    local location = ""

    if comment.file then
      if comment.line then
        location = string.format("%s:%d", comment.file, comment.line)
      else
        location = comment.file
      end
    end

    if location ~= "" then
      table.insert(lines, string.format("%d. [%s] %s - %s", i, type_label, location, comment.body))
    else
      table.insert(lines, string.format("%d. [%s] %s", i, type_label, comment.body))
    end
  end

  return table.concat(lines, "\n")
end

---Generate JSON export
---@param opts? Review.ExportOptions
---@return string
function M.generate_json(opts)
  opts = opts or {}

  local comments = state.state.comments

  if opts.only_pending then
    comments = vim.tbl_filter(function(c)
      return c.kind == "local" and c.status == "pending"
    end, comments)
  end

  local data = {
    mode = state.state.mode,
    pr = state.state.pr,
    files = state.state.files,
    comments = comments,
    exported_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }

  return vim.json.encode(data)
end

---Generate export in specified format
---@param opts? Review.ExportOptions
---@return string
function M.generate(opts)
  opts = opts or {}
  local format = opts.format or "markdown"

  if format == "json" then
    return M.generate_json(opts)
  elseif format == "plain" then
    return M.generate_plain(opts)
  else
    return M.generate_markdown(opts)
  end
end

---Get the diff for current review
---@return string
function M.get_diff()
  if state.state.mode == "pr" and state.state.pr then
    local github = require("review.integrations.github")
    return github.fetch_pr_diff(state.state.pr.number)
  else
    local git = require("review.integrations.git")
    return git.diff(state.state.base)
  end
end

---Export to clipboard
---@param opts? Review.ExportOptions
function M.to_clipboard(opts)
  local content = M.generate(opts)
  local count = #vim.tbl_filter(function(c)
    return c.kind == "local" or c.file ~= nil
  end, state.state.comments)

  if count == 0 and not (opts and opts.include_diff) then
    vim.notify("No comments to export", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", content)
  vim.fn.setreg("*", content)

  vim.notify(string.format("Exported %d comment(s) to clipboard", count), vim.log.levels.INFO)
end

---Preview export in a split buffer
---@param opts? Review.ExportOptions
function M.preview(opts)
  opts = opts or {}
  local content = M.generate(opts)
  local format = opts.format or "markdown"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))

  local filetype = "markdown"
  if format == "json" then
    filetype = "json"
  elseif format == "plain" then
    filetype = "text"
  end

  vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_buf_set_name(buf, "Review Export")

  -- Remember current window for restoration
  local prev_win = vim.api.nvim_get_current_win()

  -- Open in a bottom split
  local line_count = #vim.split(content, "\n")
  local height = math.min(line_count + 1, 20)
  vim.cmd("botright " .. height .. "split")
  vim.api.nvim_win_set_buf(0, buf)

  -- Map q to close
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(0, true)
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end, { buffer = buf, nowait = true })
end

---Get a summary of comments by type
---@return table<string, number>
function M.get_comment_summary()
  local summary = {
    issue = 0,
    suggestion = 0,
    note = 0,
    praise = 0,
    other = 0,
    total = 0,
  }

  for _, comment in ipairs(state.state.comments) do
    if comment.kind == "local" then
      local type = comment.type or "note"
      if summary[type] then
        summary[type] = summary[type] + 1
      else
        summary.other = summary.other + 1
      end
      summary.total = summary.total + 1
    end
  end

  return summary
end

return M
