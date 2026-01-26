-- Line tracker for review.nvim
-- Uses Neovim extmarks to track comment positions through buffer edits
local M = {}

local state = require("review.core.state")
local ns_id = vim.api.nvim_create_namespace("review_line_tracker")

---@class Review.TrackedComment
---@field comment_id string Comment ID
---@field extmark_id number Extmark ID
---@field original_line number Original line number

---@type table<number, Review.TrackedComment[]> buf -> tracked comments
M._tracked = {}

---Create extmark for a comment to track its position
---@param buf number Buffer handle
---@param comment Review.Comment
---@return number? extmark_id
function M.track_comment(buf, comment)
  if not comment.line then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- Check if line is within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(buf)
  local line = math.min(comment.line, line_count)

  local ok, extmark_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line - 1, 0, {
    -- Right gravity: extmark stays with the line when text is inserted before it
    right_gravity = true,
    -- End line for range tracking (if multi-line comment)
    end_row = comment.end_line and (math.min(comment.end_line, line_count) - 1) or nil,
  })

  if not ok then
    return nil
  end

  -- Store the tracking info
  M._tracked[buf] = M._tracked[buf] or {}
  table.insert(M._tracked[buf], {
    comment_id = comment.id,
    extmark_id = extmark_id,
    original_line = comment.line,
  })

  -- Store extmark_id on comment for reverse lookup
  comment.extmark_id = extmark_id

  return extmark_id
end

---Get current line number for a tracked comment
---@param buf number Buffer handle
---@param comment Review.Comment
---@return number? line Current line number (1-indexed) or nil if extmark deleted
function M.get_current_line(buf, comment)
  if not comment.extmark_id then
    return comment.line
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return comment.line
  end

  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, buf, ns_id, comment.extmark_id, {})
  if not ok or #mark == 0 then
    return nil -- Extmark was deleted (line was deleted)
  end

  return mark[1] + 1 -- Convert 0-indexed to 1-indexed
end

---Get current end line for a tracked multi-line comment
---@param buf number Buffer handle
---@param comment Review.Comment
---@return number? end_line Current end line (1-indexed) or nil
function M.get_current_end_line(buf, comment)
  if not comment.extmark_id or not comment.end_line then
    return comment.end_line
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return comment.end_line
  end

  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, buf, ns_id, comment.extmark_id, {
    details = true,
  })
  if not ok or #mark == 0 then
    return nil
  end

  -- mark[3] contains details including end_row if set
  if mark[3] and mark[3].end_row then
    return mark[3].end_row + 1
  end

  return comment.end_line
end

---Update all comment line numbers from their extmarks
---@param buf number Buffer handle
function M.sync_comment_lines(buf)
  local file = state.state.current_file
  if not file then
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local comments = state.get_comments_for_file(file)
  for _, comment in ipairs(comments) do
    if comment.extmark_id then
      local current_line = M.get_current_line(buf, comment)
      if current_line then
        comment.line = current_line
      end

      -- Also update end_line for multi-line comments
      local current_end = M.get_current_end_line(buf, comment)
      if current_end then
        comment.end_line = current_end
      end
    end
  end
end

---Track all comments for current file
---@param buf number Buffer handle
function M.track_all_comments(buf)
  local file = state.state.current_file
  if not file then
    return
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear existing extmarks for this buffer
  M.clear(buf)

  local comments = state.get_comments_for_file(file)
  for _, comment in ipairs(comments) do
    M.track_comment(buf, comment)
  end
end

---Clear all tracking for a buffer
---@param buf number Buffer handle
function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns_id, 0, -1)
  end
  M._tracked[buf] = nil
end

---Clear tracking for a specific comment
---@param buf number Buffer handle
---@param comment_id string Comment ID
function M.untrack_comment(buf, comment_id)
  if not M._tracked[buf] then
    return
  end

  for i, tracked in ipairs(M._tracked[buf]) do
    if tracked.comment_id == comment_id then
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns_id, tracked.extmark_id)
      end
      table.remove(M._tracked[buf], i)
      break
    end
  end
end

---Check if a comment has moved from its original position
---@param buf number Buffer handle
---@param comment Review.Comment
---@return boolean has_moved, number? delta How many lines it moved
function M.has_comment_moved(buf, comment)
  if not comment.extmark_id then
    return false, nil
  end

  local tracked = M._tracked[buf]
  if not tracked then
    return false, nil
  end

  for _, t in ipairs(tracked) do
    if t.comment_id == comment.id then
      local current_line = M.get_current_line(buf, comment)
      if current_line then
        local delta = current_line - t.original_line
        return delta ~= 0, delta
      end
      break
    end
  end

  return false, nil
end

---Get all tracked comments for a buffer
---@param buf number Buffer handle
---@return Review.TrackedComment[]
function M.get_tracked(buf)
  return M._tracked[buf] or {}
end

---Setup autocmds for automatic line syncing
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("ReviewLineTracker", { clear = true })

  -- Sync lines on buffer write
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*",
    callback = function(args)
      if state.is_active() and state.state.current_file then
        M.sync_comment_lines(args.buf)

        -- Refresh UI to show updated positions
        local ok_signs, signs = pcall(require, "review.ui.signs")
        if ok_signs then
          signs.refresh()
        end

        local ok_vt, virtual_text = pcall(require, "review.ui.virtual_text")
        if ok_vt then
          virtual_text.refresh()
        end
      end
    end,
  })

  -- Track comments when opening diff buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function(args)
      if state.is_active() and state.state.current_file then
        local file = vim.api.nvim_buf_get_name(args.buf)
        if file and file:find(state.state.current_file, 1, true) then
          -- Re-track comments when entering the buffer
          M.track_all_comments(args.buf)
        end
      end
    end,
  })

  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "*",
    callback = function(args)
      M.clear(args.buf)
    end,
  })
end

---Clean up autocmds
function M.cleanup_autocmds()
  pcall(vim.api.nvim_del_augroup_by_name, "ReviewLineTracker")
end

---Get the namespace ID for external use
---@return number
function M.get_namespace()
  return ns_id
end

return M
