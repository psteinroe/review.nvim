-- PR info panel for review.nvim
local M = {}

local state = require("review.core.state")
local utils = require("review.utils")
local float = require("review.ui.float")

-- Namespace for panel extmarks
local ns_id = vim.api.nvim_create_namespace("review_panel")

---@type table<number, Review.Comment> Line number to comment mapping for cursor actions
local line_to_comment = {}

---Get the namespace ID
---@return number
function M.get_namespace()
  return ns_id
end

---Toggle PR panel
function M.toggle()
  if state.state.panel_open then
    M.close()
  else
    M.open()
  end
end

---Check if panel is open
---@return boolean
function M.is_open()
  return state.state.panel_open
end

---Open PR panel
function M.open()
  local lines, comment_map = M.render()
  line_to_comment = comment_map

  local width = 80
  local height = math.min(#lines, 40)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "review_panel"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  -- Center the window in the editor
  local editor_height = vim.o.lines
  local editor_width = vim.o.columns
  local row = math.floor((editor_height - height) / 2)
  local col = math.floor((editor_width - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })

  state.state.layout.panel_win = win
  state.state.layout.panel_buf = buf
  state.state.panel_open = true

  -- Set window options
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true

  -- Setup panel keymaps
  M.setup_keymaps(buf)

  -- Apply highlights
  M.apply_highlights(buf, lines)
end

---Close PR panel
function M.close()
  if state.state.layout.panel_win and vim.api.nvim_win_is_valid(state.state.layout.panel_win) then
    vim.api.nvim_win_close(state.state.layout.panel_win, true)
  end
  state.state.panel_open = false
  state.state.layout.panel_win = nil
  state.state.layout.panel_buf = nil
  line_to_comment = {}
end

---Render panel content
---@return string[] lines
---@return table<number, Review.Comment> comment_map Line to comment mapping
function M.render()
  local lines = {}
  local comment_map = {}
  local pr = state.state.pr

  if not pr then
    -- Local mode - simpler panel
    return M.render_local_panel()
  end

  -- PR Header
  table.insert(lines, string.format(" PR #%d: %s ", pr.number, pr.title))
  table.insert(lines, string.rep("-", 78))
  table.insert(
    lines,
    string.format(
      " @%s -> %s | %s | +%d -%d | %d files",
      pr.author,
      pr.base,
      utils.relative_time(pr.created_at),
      pr.additions or 0,
      pr.deletions or 0,
      pr.changed_files or 0
    )
  )
  table.insert(lines, string.rep("-", 78))

  -- Description
  table.insert(lines, " [DESCRIPTION]")
  table.insert(lines, "")
  if pr.description and pr.description ~= "" then
    for line in pr.description:gmatch("[^\n]+") do
      table.insert(lines, "   " .. line)
    end
  else
    table.insert(lines, "   (no description)")
  end
  table.insert(lines, "")
  table.insert(lines, string.rep("-", 78))

  -- Conversation comments
  local conversation = vim.tbl_filter(function(c)
    return c.kind == "conversation" or c.kind == "review_summary"
  end, state.state.comments)

  if #conversation > 0 then
    table.insert(lines, string.format(" [CONVERSATION] (%d)", #conversation))
    table.insert(lines, "")
    for _, comment in ipairs(conversation) do
      M.render_comment(comment, lines, comment_map, false)
    end
    table.insert(lines, string.rep("-", 78))
  end

  -- Code comments
  local code_comments = vim.tbl_filter(function(c)
    return c.kind == "review" and c.file
  end, state.state.comments)

  if #code_comments > 0 then
    table.insert(lines, string.format(" [CODE COMMENTS] (%d)", #code_comments))
    table.insert(lines, "")
    for _, comment in ipairs(code_comments) do
      M.render_comment(comment, lines, comment_map, true)
    end
    table.insert(lines, string.rep("-", 78))
  end

  -- Pending comments
  local pending = vim.tbl_filter(function(c)
    return c.kind == "local" and c.status == "pending"
  end, state.state.comments)

  if #pending > 0 then
    table.insert(lines, string.format(" [MY PENDING] (%d)", #pending))
    table.insert(lines, "")
    for _, comment in ipairs(pending) do
      M.render_comment(comment, lines, comment_map, true)
    end
    table.insert(lines, string.rep("-", 78))
  end

  -- Actions footer
  table.insert(lines, "")
  table.insert(lines, " [a]pprove [x]request changes [g]comment [c]onversation [s]end AI [q]uit")

  return lines, comment_map
end

---Render single comment
---@param comment Review.Comment
---@param lines string[]
---@param comment_map table<number, Review.Comment>
---@param show_location boolean
function M.render_comment(comment, lines, comment_map, show_location)
  -- Track the starting line for this comment
  local start_line = #lines + 1

  local header = "   +"
  if show_location and comment.file then
    local file = type(comment.file) == "string" and comment.file or "unknown"
    local line_num = type(comment.line) == "number" and comment.line or 0
    header = header .. string.format(" %s:%d --", file, line_num)
  end
  local author = type(comment.author) == "string" and comment.author or "unknown"
  header = header .. string.format(" @%s -- %s ", author, utils.relative_time(comment.created_at))

  -- Review state badge
  if comment.review_state then
    local badges = {
      APPROVED = "[APPROVED]",
      CHANGES_REQUESTED = "[CHANGES REQUESTED]",
      COMMENTED = "[COMMENTED]",
    }
    header = header .. (badges[comment.review_state] or "")
  end

  table.insert(lines, header)
  comment_map[#lines] = comment

  -- Body
  local body = type(comment.body) == "string" and comment.body or ""
  if body ~= "" then
    for line in body:gmatch("[^\n]+") do
      table.insert(lines, "   | " .. line)
      comment_map[#lines] = comment
    end
  else
    table.insert(lines, "   | (no content)")
    comment_map[#lines] = comment
  end

  -- Replies
  if comment.replies and #comment.replies > 0 then
    for _, reply in ipairs(comment.replies) do
      local reply_author = type(reply.author) == "string" and reply.author or "anonymous"
      local reply_body = type(reply.body) == "string" and reply.body or ""
      table.insert(lines, string.format("   |   > @%s: %s", reply_author, utils.truncate(reply_body, 50)))
      comment_map[#lines] = comment
    end
  end

  -- Actions
  local actions = "   | "
  if comment.kind == "local" then
    actions = actions .. "[e]dit [d]elete"
  else
    actions = actions .. "[r]eply"
    if comment.resolved ~= nil then
      actions = actions .. " [R]esolve"
      actions = actions .. (comment.resolved and "  [resolved]" or "  [unresolved]")
    end
  end
  table.insert(lines, actions)
  comment_map[#lines] = comment

  table.insert(lines, "   +" .. string.rep("-", 70))
  table.insert(lines, "")
end

---Render panel for local mode (no PR)
---@return string[] lines
---@return table<number, Review.Comment> comment_map
function M.render_local_panel()
  local lines = {}
  local comment_map = {}

  table.insert(lines, " Local Review ")
  table.insert(lines, string.rep("-", 78))
  table.insert(lines, string.format(" Base: %s | %d files changed", state.state.base, #state.state.files))
  table.insert(lines, string.rep("-", 78))

  -- Pending comments
  local pending = state.get_pending_comments()
  if #pending > 0 then
    table.insert(lines, string.format(" [COMMENTS] (%d)", #pending))
    table.insert(lines, "")
    for _, comment in ipairs(pending) do
      M.render_comment(comment, lines, comment_map, true)
    end
  else
    table.insert(lines, "")
    table.insert(lines, " No comments yet. Press 'q' to close.")
  end

  table.insert(lines, "")
  table.insert(lines, " [s]end to AI [q]uit")

  return lines, comment_map
end

---Setup keymaps for panel buffer
---@param buf number
function M.setup_keymaps(buf)
  local opts = { buffer = buf, nowait = true }

  -- Close
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  -- GitHub actions (only in PR mode)
  vim.keymap.set("n", "a", function()
    M.close()
    local github = utils.safe_require("review.integrations.github")
    if github then
      github.approve()
    end
  end, opts)

  vim.keymap.set("n", "x", function()
    M.close()
    local github = utils.safe_require("review.integrations.github")
    if github then
      github.request_changes()
    end
  end, opts)

  vim.keymap.set("n", "c", function()
    M.close()
    local github = utils.safe_require("review.integrations.github")
    if github then
      github.add_conversation_comment()
    end
  end, opts)

  vim.keymap.set("n", "g", function()
    M.close()
    local github = utils.safe_require("review.integrations.github")
    if github then
      github.comment()
    end
  end, opts)

  -- AI actions
  vim.keymap.set("n", "s", function()
    M.close()
    local ai = utils.safe_require("review.integrations.ai")
    if ai then
      ai.send_to_ai()
    else
      -- Fallback: copy to clipboard
      local prompt = M.build_ai_prompt()
      vim.fn.setreg("+", prompt)
      vim.fn.setreg("*", prompt)
      vim.notify("Review copied to clipboard", vim.log.levels.INFO)
    end
  end, opts)

  -- Comment actions at cursor
  vim.keymap.set("n", "r", function()
    M.reply_at_cursor()
  end, opts)

  vim.keymap.set("n", "R", function()
    M.resolve_at_cursor()
  end, opts)

  vim.keymap.set("n", "e", function()
    M.edit_at_cursor()
  end, opts)

  vim.keymap.set("n", "d", function()
    M.delete_at_cursor()
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    M.goto_at_cursor()
  end, opts)
end

---Build a simple AI prompt from current state
---@return string
function M.build_ai_prompt()
  local lines = { "# Code Review", "" }

  if state.state.pr then
    table.insert(lines, string.format("PR #%d: %s", state.state.pr.number, state.state.pr.title))
    table.insert(lines, "")
  end

  local pending = state.get_pending_comments()
  if #pending > 0 then
    table.insert(lines, "## Comments to Address")
    table.insert(lines, "")
    for i, comment in ipairs(pending) do
      local location = ""
      if comment.file then
        location = string.format(" (%s:%d)", comment.file, comment.line or 0)
      end
      table.insert(lines, string.format("%d. %s%s", i, comment.body, location))
    end
  end

  return table.concat(lines, "\n")
end

---Get comment at cursor position
---@return Review.Comment?
function M.get_comment_at_cursor()
  if not state.state.layout.panel_win or not vim.api.nvim_win_is_valid(state.state.layout.panel_win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(state.state.layout.panel_win)
  local line_num = cursor[1]

  return line_to_comment[line_num]
end

---Reply to comment at cursor
function M.reply_at_cursor()
  local comment = M.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.WARN)
    return
  end

  if comment.kind == "local" then
    vim.notify("Cannot reply to local comments", vim.log.levels.WARN)
    return
  end

  M.close()

  float.multiline_input({ prompt = "Reply" }, function(lines)
    if not lines or #lines == 0 then
      return
    end
    local body = table.concat(lines, "\n")

    local github = utils.safe_require("review.integrations.github")
    if github and comment.github_id then
      github.reply_to_comment(comment.github_id, body)
    else
      vim.notify("Cannot reply: GitHub integration not available", vim.log.levels.ERROR)
    end
  end)
end

---Resolve comment at cursor
function M.resolve_at_cursor()
  local comment = M.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.WARN)
    return
  end

  if comment.kind == "local" then
    vim.notify("Cannot resolve local comments", vim.log.levels.WARN)
    return
  end

  if comment.resolved == nil then
    vim.notify("Comment is not resolvable", vim.log.levels.WARN)
    return
  end

  local github = utils.safe_require("review.integrations.github")
  if github and comment.thread_id then
    github.resolve_thread(comment.thread_id, not comment.resolved)
    M.refresh()
  else
    -- Toggle locally for display purposes
    comment.resolved = not comment.resolved
    M.refresh()
  end
end

---Edit comment at cursor
function M.edit_at_cursor()
  local comment = M.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.WARN)
    return
  end

  if comment.kind ~= "local" then
    vim.notify("Can only edit local comments", vim.log.levels.WARN)
    return
  end

  M.close()

  float.multiline_input({ prompt = "Edit Comment", default = comment.body }, function(lines)
    if not lines then
      return
    end
    local comments = require("review.core.comments")
    comments.edit(comment.id, table.concat(lines, "\n"))
  end)
end

---Delete comment at cursor
function M.delete_at_cursor()
  local comment = M.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.WARN)
    return
  end

  if comment.kind ~= "local" then
    vim.notify("Can only delete local comments", vim.log.levels.WARN)
    return
  end

  float.confirm("Delete this comment?", function(confirmed)
    if confirmed then
      local comments = require("review.core.comments")
      comments.delete(comment.id)
      M.refresh()
    end
  end)
end

---Jump to comment location
function M.goto_at_cursor()
  local comment = M.get_comment_at_cursor()
  if not comment then
    vim.notify("No comment at cursor", vim.log.levels.WARN)
    return
  end

  if not comment.file then
    vim.notify("Comment has no file location", vim.log.levels.WARN)
    return
  end

  M.close()

  local navigation = utils.safe_require("review.core.navigation")
  if navigation then
    navigation.goto_comment(comment, 0)
  else
    -- Fallback: try to open file directly
    local diff = utils.safe_require("review.ui.diff")
    if diff then
      diff.open_file(comment.file)
      if comment.line then
        vim.api.nvim_win_set_cursor(0, { comment.line, 0 })
      end
    end
  end
end

---Refresh panel content
function M.refresh()
  if not state.state.panel_open then
    return
  end
  local buf = state.state.layout.panel_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines, comment_map = M.render()
  line_to_comment = comment_map

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  M.apply_highlights(buf, lines)
end

---Apply syntax highlighting to panel
---@param buf number
---@param lines string[]
function M.apply_highlights(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  for i, line in ipairs(lines) do
    local row = i - 1

    -- Headers (section titles)
    if line:match("^%s*%[%u+") then
      vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
        end_col = #line,
        hl_group = "ReviewPanelSection",
      })
    end

    -- PR title line
    if line:match("^%s*PR #%d+:") then
      vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
        end_col = #line,
        hl_group = "ReviewPanelHeader",
      })
    end

    -- Author mentions
    local author_start = line:find("@%w+")
    if author_start then
      local author_end = line:find("[^%w]", author_start + 1) or #line + 1
      vim.api.nvim_buf_set_extmark(buf, ns_id, row, author_start - 1, {
        end_col = author_end - 1,
        hl_group = "ReviewPanelAuthor",
      })
    end

    -- Timestamps (relative time patterns)
    local time_patterns = {
      "just now",
      "%d+ %w+ ago",
      "yesterday",
      "in the future",
      "unknown",
    }
    for _, pattern in ipairs(time_patterns) do
      local s, e = line:find(pattern)
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns_id, row, s - 1, {
          end_col = e,
          hl_group = "ReviewPanelTime",
        })
        break
      end
    end

    -- Resolved/unresolved status
    if line:find("%[resolved%]") then
      local s, e = line:find("%[resolved%]")
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns_id, row, s - 1, {
          end_col = e,
          hl_group = "ReviewPanelResolved",
        })
      end
    elseif line:find("%[unresolved%]") then
      local s, e = line:find("%[unresolved%]")
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns_id, row, s - 1, {
          end_col = e,
          hl_group = "ReviewPanelUnresolved",
        })
      end
    end

    -- Review state badges
    if line:find("%[APPROVED%]") then
      local s, e = line:find("%[APPROVED%]")
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns_id, row, s - 1, {
          end_col = e,
          hl_group = "ReviewPanelResolved",
        })
      end
    elseif line:find("%[CHANGES REQUESTED%]") then
      local s, e = line:find("%[CHANGES REQUESTED%]")
      if s then
        vim.api.nvim_buf_set_extmark(buf, ns_id, row, s - 1, {
          end_col = e,
          hl_group = "ReviewPanelUnresolved",
        })
      end
    end

    -- Separator lines
    if line:match("^%-+$") or line:match("^%s*%+%-+$") then
      vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
        end_col = #line,
        hl_group = "Comment",
      })
    end
  end
end

return M
