-- Comment CRUD operations for review.nvim
local M = {}

local state = require("review.core.state")
local utils = require("review.utils")

---Add a local comment
---@param file string File path
---@param line number Line number
---@param body string Comment text
---@param type? "note" | "issue" | "suggestion" | "praise" Comment type
---@return Review.Comment
function M.add(file, line, body, type)
  local comment = {
    id = utils.generate_id("local"),
    kind = "local",
    file = file,
    line = line,
    body = body,
    type = type or "note",
    status = "pending",
    author = "you",
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  state.add_comment(comment)
  return comment
end

---Add a multi-line local comment
---@param file string File path
---@param start_line number Start line number
---@param end_line number End line number
---@param body string Comment text
---@param type? "note" | "issue" | "suggestion" | "praise" Comment type
---@return Review.Comment
function M.add_multiline(file, start_line, end_line, body, type)
  local comment = {
    id = utils.generate_id("local"),
    kind = "local",
    file = file,
    line = start_line,
    start_line = start_line,
    end_line = end_line,
    body = body,
    type = type or "note",
    status = "pending",
    author = "you",
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  state.add_comment(comment)
  return comment
end

---Edit a comment body
---@param id string Comment ID
---@param body string New comment text
---@return boolean success
function M.edit(id, body)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end

  -- Only allow editing local comments
  if comment.kind ~= "local" then
    return false
  end

  comment.body = body
  comment.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  state.auto_save()
  return true
end

---Delete a comment
---@param id string Comment ID
---@return boolean success
function M.delete(id)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end

  -- Only allow deleting local pending comments
  if comment.kind ~= "local" or comment.status ~= "pending" then
    return false
  end

  return state.remove_comment(id)
end

---Reply to a comment thread
---@param parent_id string Parent comment ID
---@param body string Reply text
---@return Review.Comment? reply The created reply or nil on failure
function M.reply(parent_id, body)
  local parent = state.find_comment(parent_id)
  if not parent then
    return nil
  end

  local reply = {
    id = utils.generate_id("reply"),
    kind = "local",
    body = body,
    author = "you",
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    in_reply_to_id = parent_id,
    file = parent.file,
    line = parent.line,
    status = "pending",
  }

  -- Add reply to parent's replies list
  if not parent.replies then
    parent.replies = {}
  end
  table.insert(parent.replies, reply)

  -- Also add to global comments list for tracking
  state.add_comment(reply)

  return reply
end

---Set resolved status for a comment thread
---@param id string Comment ID (thread root)
---@param resolved boolean New resolved status
---@return boolean success
function M.set_resolved(id, resolved)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end

  -- Only review comments from GitHub can be resolved
  if comment.kind ~= "review" then
    return false
  end

  comment.resolved = resolved
  return true
end

---Change comment type
---@param id string Comment ID
---@param type "note" | "issue" | "suggestion" | "praise" New type
---@return boolean success
function M.set_type(id, type)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end

  -- Only local comments can have their type changed
  if comment.kind ~= "local" then
    return false
  end

  comment.type = type
  comment.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  state.auto_save()
  return true
end

---Mark a local comment as submitted (after GitHub submission)
---@param id string Comment ID
---@param github_id? number GitHub comment ID
---@return boolean success
function M.mark_submitted(id, github_id)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end

  if comment.kind ~= "local" then
    return false
  end

  comment.status = "submitted"
  if github_id then
    comment.github_id = github_id
  end
  state.auto_save()
  return true
end

---Get all comments for a specific line
---@param file string File path
---@param line number Line number
---@return Review.Comment[]
function M.get_at_line(file, line)
  local comments = state.get_comments_for_file(file)
  return vim.tbl_filter(function(c)
    -- Ensure line numbers are actual numbers (not userdata from JSON)
    local c_line = tonumber(c.line)
    local c_start = tonumber(c.start_line)
    local c_end = tonumber(c.end_line)

    -- Single line comment
    if c_line == line and not c_start then
      return true
    end
    -- Multi-line comment: check if line is within range
    if c_start and c_end then
      return line >= c_start and line <= c_end
    end
    return false
  end, comments)
end

---Check if a comment is editable (local and pending)
---@param id string Comment ID
---@return boolean
function M.is_editable(id)
  local comment = state.find_comment(id)
  if not comment then
    return false
  end
  return comment.kind == "local" and comment.status == "pending"
end

---Check if a comment is deletable
---@param id string Comment ID
---@return boolean
function M.is_deletable(id)
  return M.is_editable(id)
end

---Get the thread root for a reply
---@param reply_id string Reply comment ID
---@return Review.Comment? root The thread root comment or nil
function M.get_thread_root(reply_id)
  local reply = state.find_comment(reply_id)
  if not reply or not reply.in_reply_to_id then
    return reply
  end

  -- Walk up the reply chain to find root
  local current = reply
  while current and current.in_reply_to_id do
    current = state.find_comment(current.in_reply_to_id)
  end

  return current
end

---Count replies in a thread
---@param root_id string Root comment ID
---@return number
function M.count_replies(root_id)
  local root = state.find_comment(root_id)
  if not root or not root.replies then
    return 0
  end
  return #root.replies
end

return M
