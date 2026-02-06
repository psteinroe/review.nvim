-- Navigation module for review.nvim
-- Handles comment, hunk, and file navigation

local M = {}

local state = require("review.core.state")
local utils = require("review.utils")

---Go to next comment (across all files)
---Wraps around to the first comment when reaching the end
function M.next_comment()
  local comments = state.get_comments_sorted()
  if #comments == 0 then
    vim.notify("No comments", vim.log.levels.INFO)
    return
  end

  local current_idx = state.state.current_comment_idx or 0
  local next_idx = current_idx + 1
  if next_idx > #comments then
    next_idx = 1 -- Wrap around
  end

  M.goto_comment(comments[next_idx], next_idx)
end

---Go to previous comment (across all files)
---Wraps around to the last comment when reaching the beginning
function M.prev_comment()
  local comments = state.get_comments_sorted()
  if #comments == 0 then
    vim.notify("No comments", vim.log.levels.INFO)
    return
  end

  local current_idx = state.state.current_comment_idx or 1
  local prev_idx = current_idx - 1
  if prev_idx < 1 then
    prev_idx = #comments -- Wrap around
  end

  M.goto_comment(comments[prev_idx], prev_idx)
end

---Go to next unresolved comment
function M.next_unresolved()
  local all_unresolved = state.get_unresolved_comments()
  if #all_unresolved == 0 then
    vim.notify("No unresolved comments", vim.log.levels.INFO)
    return
  end

  -- Sort by file, then line
  table.sort(all_unresolved, function(a, b)
    local a_file = type(a.file) == "string" and a.file or ""
    local b_file = type(b.file) == "string" and b.file or ""
    if a_file ~= b_file then
      return a_file < b_file
    end
    return (tonumber(a.line) or 0) < (tonumber(b.line) or 0)
  end)

  -- Find current position and get next
  local current_file = state.state.current_file
  local current_line = M.get_cursor_line() or 0

  for i, comment in ipairs(all_unresolved) do
    local is_after = false
    if comment.file and current_file then
      if comment.file > current_file then
        is_after = true
      elseif comment.file == current_file and (comment.line or 0) > current_line then
        is_after = true
      end
    elseif comment.file then
      is_after = true
    end

    if is_after then
      M.goto_comment(comment, i)
      return
    end
  end

  -- Wrap around to first
  M.goto_comment(all_unresolved[1], 1)
end

---Go to previous unresolved comment
function M.prev_unresolved()
  local all_unresolved = state.get_unresolved_comments()
  if #all_unresolved == 0 then
    vim.notify("No unresolved comments", vim.log.levels.INFO)
    return
  end

  -- Sort by file, then line (descending for prev)
  table.sort(all_unresolved, function(a, b)
    local a_file = type(a.file) == "string" and a.file or ""
    local b_file = type(b.file) == "string" and b.file or ""
    if a_file ~= b_file then
      return a_file > b_file
    end
    return (tonumber(a.line) or 0) > (tonumber(b.line) or 0)
  end)

  -- Find current position and get previous
  local current_file = state.state.current_file
  local current_line = M.get_cursor_line() or math.huge

  for i, comment in ipairs(all_unresolved) do
    local is_before = false
    if comment.file and current_file then
      if comment.file < current_file then
        is_before = true
      elseif comment.file == current_file and (comment.line or 0) < current_line then
        is_before = true
      end
    end

    if is_before then
      M.goto_comment(comment, i)
      return
    end
  end

  -- Wrap around to last (first in descending order)
  M.goto_comment(all_unresolved[1], 1)
end

---Go to next pending (local) comment
function M.next_pending()
  local pending = state.get_pending_comments()
  if #pending == 0 then
    vim.notify("No pending comments", vim.log.levels.INFO)
    return
  end

  -- Sort by file, then line
  table.sort(pending, function(a, b)
    local a_file = type(a.file) == "string" and a.file or ""
    local b_file = type(b.file) == "string" and b.file or ""
    if a_file ~= b_file then
      return a_file < b_file
    end
    return (tonumber(a.line) or 0) < (tonumber(b.line) or 0)
  end)

  -- Find current position and get next
  local current_file = state.state.current_file
  local current_line = M.get_cursor_line() or 0

  for i, comment in ipairs(pending) do
    local is_after = false
    if comment.file and current_file then
      if comment.file > current_file then
        is_after = true
      elseif comment.file == current_file and (comment.line or 0) > current_line then
        is_after = true
      end
    elseif comment.file then
      is_after = true
    end

    if is_after then
      M.goto_comment(comment, i)
      return
    end
  end

  -- Wrap around to first
  M.goto_comment(pending[1], 1)
end

---Go to previous pending (local) comment
function M.prev_pending()
  local pending = state.get_pending_comments()
  if #pending == 0 then
    vim.notify("No pending comments", vim.log.levels.INFO)
    return
  end

  -- Sort by file, then line (descending)
  table.sort(pending, function(a, b)
    local a_file = type(a.file) == "string" and a.file or ""
    local b_file = type(b.file) == "string" and b.file or ""
    if a_file ~= b_file then
      return a_file > b_file
    end
    return (tonumber(a.line) or 0) > (tonumber(b.line) or 0)
  end)

  -- Find current position and get previous
  local current_file = state.state.current_file
  local current_line = M.get_cursor_line() or math.huge

  for i, comment in ipairs(pending) do
    local is_before = false
    if comment.file and current_file then
      if comment.file < current_file then
        is_before = true
      elseif comment.file == current_file and (comment.line or 0) < current_line then
        is_before = true
      end
    end

    if is_before then
      M.goto_comment(comment, i)
      return
    end
  end

  -- Wrap around to last (first in descending order)
  M.goto_comment(pending[1], 1)
end

---Jump to specific comment
---@param comment Review.Comment
---@param idx? number Optional index to set as current
function M.goto_comment(comment, idx)
  if not comment then
    return
  end

  local needs_file_open = comment.file and comment.file ~= state.state.current_file

  -- Open file if different
  if needs_file_open then
    local diff = utils.safe_require("review.ui.diff")
    if diff then
      diff.open_file(comment.file)
    end
  end

  -- Update index
  if idx then
    state.state.current_comment_idx = idx
  end

  -- Schedule line jump and popup to run after file is fully loaded
  -- This ensures it runs after diff.open_file's scheduled jump_to_first_hunk
  local function jump_and_show()
    -- Jump to line
    if comment.line then
      M.goto_line(comment.line)
    end

    -- Show float popup
    local float = utils.safe_require("review.ui.float")
    if float then
      float.show_comment(comment)
    end
  end

  if needs_file_open then
    -- Double schedule to ensure we run after open_file's scheduled actions
    vim.schedule(function()
      vim.schedule(jump_and_show)
    end)
  else
    jump_and_show()
  end
end

---Get comment at current cursor line
---@return Review.Comment?
function M.get_comment_at_cursor()
  local current_file = state.state.current_file
  if not current_file then
    return nil
  end

  local line = M.get_cursor_line()
  if not line then
    return nil
  end

  local comments = require("review.core.comments")
  local at_line = comments.get_at_line(current_file, line)
  -- Return first comment at this line (if any)
  return at_line[1]
end

---Get all comments at current cursor line
---@return Review.Comment[]
function M.get_comments_at_cursor()
  local current_file = state.state.current_file
  if not current_file then
    return {}
  end

  local line = M.get_cursor_line()
  if not line then
    return {}
  end

  local file_comments = state.get_comments_for_file(current_file)
  local result = {}
  for _, comment in ipairs(file_comments) do
    if comment.line == line then
      table.insert(result, comment)
    end
  end
  return result
end

---Navigate to next hunk (uses vim's built-in diff navigation)
function M.next_hunk()
  pcall(vim.cmd, "normal! ]c")
end

---Navigate to previous hunk
function M.prev_hunk()
  pcall(vim.cmd, "normal! [c")
end

---Check if current line is part of a diff (highlighted)
---@return boolean
local function is_on_diff_line()
  local line = vim.fn.line(".")
  -- Check multiple columns since diff highlight might not start at col 1
  for col = 1, math.min(10, vim.fn.col("$")) do
    if vim.fn.diff_hlID(line, col) > 0 then
      return true
    end
  end
  return false
end

---Navigate to next hunk across files
---If at last hunk in current file, opens next file and jumps to first hunk
function M.next_hunk_across_files()
  local layout = utils.safe_require("review.ui.layout")
  if not layout then
    return
  end

  -- Ensure we're in the diff window
  layout.focus_diff()

  -- Save current view state
  local view = vim.fn.winsaveview()
  local start_line = view.lnum

  -- Try to go to next hunk
  pcall(vim.cmd, "normal! ]c")

  -- Get new position
  local new_line = vim.fn.line(".")

  -- Check if we actually moved to a diff line
  local on_diff = is_on_diff_line()

  if new_line == start_line or not on_diff then
    -- Didn't move to a new hunk - restore position and go to next file
    vim.fn.winrestview(view)
    M.open_next_file()
  end
  -- Otherwise we successfully moved to next hunk
end

---Navigate to previous hunk across files
---If at first hunk in current file, opens previous file and jumps to last hunk
function M.prev_hunk_across_files()
  local layout = utils.safe_require("review.ui.layout")
  if not layout then
    return
  end

  -- Ensure we're in the diff window
  layout.focus_diff()

  -- Save current view state
  local view = vim.fn.winsaveview()
  local start_line = view.lnum

  -- Try to go to previous hunk
  pcall(vim.cmd, "normal! [c")

  -- Get new position
  local new_line = vim.fn.line(".")

  -- Check if we actually moved to a diff line
  local on_diff = is_on_diff_line()

  if new_line == start_line or not on_diff then
    -- Didn't move to a new hunk - restore position and go to previous file
    vim.fn.winrestview(view)

    local tree = utils.safe_require("review.ui.file_tree")
    if not tree then
      return
    end

    local sorted_paths = tree.get_sorted_paths()
    if #sorted_paths == 0 then
      return
    end

    local current_idx = M.get_current_file_idx()
    local prev_idx = current_idx - 1
    if prev_idx < 1 then
      prev_idx = #sorted_paths -- Wrap around
    end

    local path = sorted_paths[prev_idx]
    if path then
      local diff = utils.safe_require("review.ui.diff")
      if diff then
        diff.open_file(path)
        -- Jump to last hunk (go to end, then find last change)
        vim.schedule(function()
          vim.cmd("normal! G")
          pcall(vim.cmd, "normal! [c")
        end)
      end

      -- Update file tree selection
      tree.set_selected_idx(prev_idx)
    end
  end
  -- Otherwise we successfully moved to previous hunk
end

---File tree navigation: select next file
function M.tree_next()
  local tree = utils.safe_require("review.ui.file_tree")
  if tree then
    tree.select_next()
  end
end

---File tree navigation: select previous file
function M.tree_prev()
  local tree = utils.safe_require("review.ui.file_tree")
  if tree then
    tree.select_prev()
  end
end

---Open next file in the file list (sorted display order)
function M.open_next_file()
  local tree = utils.safe_require("review.ui.file_tree")
  if not tree then
    return
  end

  local sorted_paths = tree.get_sorted_paths()
  if #sorted_paths == 0 then
    vim.notify("No files", vim.log.levels.INFO)
    return
  end

  local current_idx = M.get_current_file_idx()
  local next_idx = current_idx + 1
  if next_idx > #sorted_paths then
    next_idx = 1 -- Wrap around
  end

  local path = sorted_paths[next_idx]
  if path then
    local diff = utils.safe_require("review.ui.diff")
    if diff then
      diff.open_file(path)
    end

    -- Update file tree selection
    tree.set_selected_idx(next_idx)
  end
end

---Open previous file in the file list (sorted display order)
function M.open_prev_file()
  local tree = utils.safe_require("review.ui.file_tree")
  if not tree then
    return
  end

  local sorted_paths = tree.get_sorted_paths()
  if #sorted_paths == 0 then
    vim.notify("No files", vim.log.levels.INFO)
    return
  end

  local current_idx = M.get_current_file_idx()
  local prev_idx = current_idx - 1
  if prev_idx < 1 then
    prev_idx = #sorted_paths -- Wrap around
  end

  local path = sorted_paths[prev_idx]
  if path then
    local diff = utils.safe_require("review.ui.diff")
    if diff then
      diff.open_file(path)
    end

    -- Update file tree selection
    tree.set_selected_idx(prev_idx)
  end
end

---Get current file index in sorted display order
---@return number
function M.get_current_file_idx()
  local current_file = state.state.current_file
  if not current_file then
    return 0
  end

  local tree = utils.safe_require("review.ui.file_tree")
  if tree then
    return tree.get_display_idx_for_path(current_file) or 0
  end
  return 0
end

---Open file by path
---@param path string File path to open
---@return boolean success
function M.open_file(path)
  local file_data = state.find_file(path)
  if not file_data then
    vim.notify("File not found: " .. path, vim.log.levels.WARN)
    return false
  end

  local diff = utils.safe_require("review.ui.diff")
  if diff then
    return diff.open_file(path)
  end
  return false
end

---Get cursor line in current window
---@return number?
function M.get_cursor_line()
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if ok then
    return cursor[1]
  end
  return nil
end

---Jump to a specific line in the diff view
---@param line number Line number to jump to
function M.goto_line(line)
  local layout = utils.safe_require("review.ui.layout")
  if not layout then
    return
  end

  local diff_win = layout.get_diff_win()
  if not diff_win or not vim.api.nvim_win_is_valid(diff_win) then
    -- Try current window
    diff_win = vim.api.nvim_get_current_win()
  end

  local buf = vim.api.nvim_win_get_buf(diff_win)
  local line_count = vim.api.nvim_buf_line_count(buf)

  if line > 0 and line <= line_count then
    vim.api.nvim_set_current_win(diff_win)
    vim.api.nvim_win_set_cursor(diff_win, { line, 0 })
    -- Center the view
    vim.cmd("normal! zz")
  end
end

---Focus on file tree panel
function M.focus_tree()
  local layout = utils.safe_require("review.ui.layout")
  if layout then
    layout.focus_tree()
  end
end

---Focus on diff view panel
function M.focus_diff()
  local layout = utils.safe_require("review.ui.layout")
  if layout then
    layout.focus_diff()
  end
end

---Toggle between file tree and diff view
function M.toggle_focus()
  local layout = utils.safe_require("review.ui.layout")
  if not layout then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local tree_win = state.state.layout.file_tree_win
  local diff_win = layout.get_diff_win()

  if current_win == tree_win then
    layout.focus_diff()
  else
    layout.focus_tree()
  end
end

---Find next comment in current file
---@return Review.Comment?
function M.next_comment_in_file()
  local current_file = state.state.current_file
  if not current_file then
    return nil
  end

  local comments = state.get_comments_for_file(current_file)
  if #comments == 0 then
    vim.notify("No comments in this file", vim.log.levels.INFO)
    return nil
  end

  -- Sort by line
  table.sort(comments, function(a, b)
    return (tonumber(a.line) or 0) < (tonumber(b.line) or 0)
  end)

  local current_line = M.get_cursor_line() or 0

  for _, comment in ipairs(comments) do
    if (tonumber(comment.line) or 0) > current_line then
      M.goto_comment(comment)
      return comment
    end
  end

  -- Wrap around to first
  M.goto_comment(comments[1])
  return comments[1]
end

---Find previous comment in current file
---@return Review.Comment?
function M.prev_comment_in_file()
  local current_file = state.state.current_file
  if not current_file then
    return nil
  end

  local comments = state.get_comments_for_file(current_file)
  if #comments == 0 then
    vim.notify("No comments in this file", vim.log.levels.INFO)
    return nil
  end

  -- Sort by line descending
  table.sort(comments, function(a, b)
    return (tonumber(a.line) or 0) > (tonumber(b.line) or 0)
  end)

  local current_line = M.get_cursor_line() or math.huge

  for _, comment in ipairs(comments) do
    if (tonumber(comment.line) or 0) < current_line then
      M.goto_comment(comment)
      return comment
    end
  end

  -- Wrap around to last (first in descending order)
  M.goto_comment(comments[1])
  return comments[1]
end

---Get count of comments for navigation status
---@return {total: number, current: number, unresolved: number, pending: number}
function M.get_comment_counts()
  local sorted = state.get_comments_sorted()
  return {
    total = #sorted,
    current = state.state.current_comment_idx or 0,
    unresolved = #state.get_unresolved_comments(),
    pending = #state.get_pending_comments(),
  }
end

return M
