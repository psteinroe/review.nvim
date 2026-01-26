-- State management for review.nvim
local M = {}

---@class Review.Layout
---@field tabpage? number Dedicated tabpage
---@field file_tree_win? number Left panel window
---@field file_tree_buf? number Left panel buffer
---@field diff_win? number Main diff window
---@field diff_buf? number Current diff buffer
---@field panel_win? number Floating panel (if open)
---@field panel_buf? number Floating panel buffer

---@class Review.Hunk
---@field old_start number Start line in old file
---@field old_count number Lines in old file
---@field new_start number Start line in new file
---@field new_count number Lines in new file
---@field header string @@ -1,5 +1,7 @@ ...
---@field lines Review.DiffLine[] Individual lines

---@class Review.DiffLine
---@field type "context" | "add" | "delete" Line type
---@field content string Line content (without +/-)
---@field old_line? number Line number in old file
---@field new_line? number Line number in new file

---@class Review.File
---@field path string Relative file path
---@field status "added" | "modified" | "deleted" | "renamed"
---@field additions number Lines added
---@field deletions number Lines deleted
---@field old_path? string For renames
---@field comment_count number Total comments on this file
---@field hunks Review.Hunk[] Parsed diff hunks
---@field reviewed boolean Whether file has been reviewed (local: staged, PR: viewed)

---@class Review.PR
---@field number number PR number
---@field title string PR title
---@field description string PR body/description
---@field author string Author username
---@field branch string Head branch
---@field base string Base branch
---@field created_at string ISO timestamp
---@field updated_at string ISO timestamp
---@field additions number Lines added
---@field deletions number Lines deleted
---@field changed_files number File count
---@field state "open" | "closed" | "merged"
---@field review_decision? "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED"
---@field url string Web URL

---@alias Review.CommentKind "conversation" | "review" | "review_summary" | "local"

---@class Review.Comment
---@field id string Unique ID
---@field kind Review.CommentKind Type of comment
---@field body string Comment text
---@field author string Username (or "you" for local)
---@field created_at string ISO timestamp
---@field updated_at? string ISO timestamp
---@field file? string File path (for code comments)
---@field line? number Line number (single-line) or start line (multi-line)
---@field start_line? number Start line for multi-line comments
---@field end_line? number End line for multi-line comments
---@field side? "LEFT" | "RIGHT" Which side of diff
---@field commit_id? string Commit SHA
---@field extmark_id? number Neovim extmark ID for tracking position
---@field thread_id? number GitHub thread ID
---@field in_reply_to_id? number Parent comment ID
---@field resolved? boolean Thread resolved?
---@field replies? Review.Comment[] Nested replies
---@field review_state? "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED"
---@field type? "note" | "issue" | "suggestion" | "praise" Local comment type
---@field status? "pending" | "submitted" Local comment status
---@field github_id? number After submission

---@class Review.State
---@field active boolean Is a review session active?
---@field mode "local" | "pr" Local diff or GitHub PR
---@field pr_mode? "remote" | "local" PR viewing mode
---@field pr? Review.PR PR data (if mode == "pr")
---@field base string Base ref (branch/commit)
---@field files Review.File[] Changed files
---@field comments Review.Comment[] All comments
---@field current_file? string Currently open file
---@field current_comment_idx? number For ]c/[c navigation
---@field panel_open boolean Is PR panel visible?
---@field layout Review.Layout Window IDs

---@type Review.State
M.state = {
  active = false,
  mode = "local",
  pr_mode = nil,
  pr = nil,
  base = "HEAD",
  files = {},
  comments = {},
  current_file = nil,
  current_comment_idx = nil,
  panel_open = false,
  layout = {},
}

---Check if a review session is active
---@return boolean
function M.is_active()
  return M.state.active
end

---Reset state to initial values
function M.reset()
  M.state = {
    active = false,
    mode = "local",
    pr_mode = nil,
    pr = nil,
    base = "HEAD",
    files = {},
    comments = {},
    current_file = nil,
    current_comment_idx = nil,
    panel_open = false,
    layout = {},
  }
end

---Set review mode
---@param mode "local" | "pr" Review mode
---@param opts? {base?: string, pr?: Review.PR, pr_mode?: "remote" | "local"}
function M.set_mode(mode, opts)
  opts = opts or {}
  M.state.mode = mode
  if opts.base then
    M.state.base = opts.base
  end
  if opts.pr then
    M.state.pr = opts.pr
  end
  if opts.pr_mode then
    M.state.pr_mode = opts.pr_mode
  end
end

---Get comments sorted by file, then line
---Used for ]c/[c navigation
---@return Review.Comment[]
function M.get_comments_sorted()
  local comments = vim.tbl_filter(function(c)
    return c.file ~= nil and c.line ~= nil
  end, M.state.comments)

  table.sort(comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return (a.line or 0) < (b.line or 0)
  end)

  return comments
end

---Get comments for a specific file
---@param file string File path
---@return Review.Comment[]
function M.get_comments_for_file(file)
  return vim.tbl_filter(function(c)
    return c.file == file
  end, M.state.comments)
end

---Get unresolved comments
---@return Review.Comment[]
function M.get_unresolved_comments()
  return vim.tbl_filter(function(c)
    return c.resolved == false and c.file ~= nil
  end, M.state.comments)
end

---Get local pending comments
---@return Review.Comment[]
function M.get_pending_comments()
  return vim.tbl_filter(function(c)
    return c.kind == "local" and c.status == "pending"
  end, M.state.comments)
end

---Add a comment to state
---@param comment Review.Comment
function M.add_comment(comment)
  table.insert(M.state.comments, comment)
  M.update_file_comment_counts()
end

---Find a comment by ID
---@param id string Comment ID
---@return Review.Comment?
---@return number? index Index in comments table
function M.find_comment(id)
  for i, comment in ipairs(M.state.comments) do
    if comment.id == id then
      return comment, i
    end
  end
  return nil, nil
end

---Remove a comment by ID
---@param id string Comment ID
---@return boolean success
function M.remove_comment(id)
  local _, idx = M.find_comment(id)
  if idx then
    table.remove(M.state.comments, idx)
    M.update_file_comment_counts()
    return true
  end
  return false
end

---Update comment counts for each file
function M.update_file_comment_counts()
  -- Reset counts
  for _, file in ipairs(M.state.files) do
    file.comment_count = 0
  end

  -- Count comments per file
  for _, comment in ipairs(M.state.comments) do
    if comment.file then
      for _, file in ipairs(M.state.files) do
        if file.path == comment.file then
          file.comment_count = file.comment_count + 1
          break
        end
      end
    end
  end
end

---Add a file to state
---@param file Review.File
function M.add_file(file)
  table.insert(M.state.files, file)
end

---Find a file by path
---@param path string File path
---@return Review.File?
---@return number? index Index in files table
function M.find_file(path)
  for i, file in ipairs(M.state.files) do
    if file.path == path then
      return file, i
    end
  end
  return nil, nil
end

---Set the current file being viewed
---@param path string File path
function M.set_current_file(path)
  M.state.current_file = path
end

---Set files list
---@param files Review.File[]
function M.set_files(files)
  M.state.files = files
  M.update_file_comment_counts()
end

---Set comments list
---@param comments Review.Comment[]
function M.set_comments(comments)
  M.state.comments = comments
  M.update_file_comment_counts()
end

---Get total stats for the review
---@return {total_files: number, total_comments: number, pending_comments: number, unresolved_comments: number, reviewed_files: number}
function M.get_stats()
  local reviewed_count = 0
  for _, file in ipairs(M.state.files) do
    if file.reviewed then
      reviewed_count = reviewed_count + 1
    end
  end
  return {
    total_files = #M.state.files,
    total_comments = #M.state.comments,
    pending_comments = #M.get_pending_comments(),
    unresolved_comments = #M.get_unresolved_comments(),
    reviewed_files = reviewed_count,
  }
end

---Set reviewed status for a file
---@param path string File path
---@param reviewed boolean
function M.set_file_reviewed(path, reviewed)
  local file = M.find_file(path)
  if file then
    file.reviewed = reviewed
  end
end

---Toggle reviewed status for a file
---@param path string File path
---@return boolean? new_status New reviewed status, or nil if file not found
function M.toggle_file_reviewed(path)
  local file = M.find_file(path)
  if file then
    file.reviewed = not file.reviewed
    return file.reviewed
  end
  return nil
end

---Get comment count for a file with pending indicator
---@param path string File path
---@return number count Total comment count
---@return boolean has_pending Whether file has pending (local) comments
function M.get_file_comment_info(path)
  local count = 0
  local has_pending = false
  for _, comment in ipairs(M.state.comments) do
    if comment.file == path then
      count = count + 1
      if comment.kind == "local" and comment.status == "pending" then
        has_pending = true
      end
    end
  end
  return count, has_pending
end

---Sync reviewed state with git staged status (for local mode)
function M.sync_reviewed_with_staged()
  if M.state.mode ~= "local" then
    return
  end
  local ok, git = pcall(require, "review.integrations.git")
  if not ok or not git.get_staged_files then
    return
  end
  local staged_files = git.get_staged_files()
  local staged_set = {}
  for _, path in ipairs(staged_files) do
    staged_set[path] = true
  end
  for _, file in ipairs(M.state.files) do
    file.reviewed = staged_set[file.path] == true
  end
end

return M
