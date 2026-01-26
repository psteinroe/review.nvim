-- Diff view rendering for review.nvim
-- Handles opening files in diff view mode

local M = {}

local state = require("review.core.state")
local config = require("review.config")
local utils = require("review.utils")
local git = require("review.integrations.git")
local layout = require("review.ui.layout")

-- Namespace for diff-related extmarks
local ns_id = vim.api.nvim_create_namespace("review_diff")

---@class Review.DiffBuffers
---@field old_buf? number Buffer for old version (base)
---@field new_buf? number Buffer for new version (current/head)
---@field old_win? number Window for old version
---@field new_win? number Window for new version

---@type Review.DiffBuffers
local diff_buffers = {}

---Convert a relative file path to absolute using git root
---@param file_path string Relative file path
---@return string Absolute file path
local function to_absolute_path(file_path)
  -- If already absolute, return as-is
  if file_path:sub(1, 1) == "/" then
    return file_path
  end
  local root = git.root_dir()
  if root then
    return root .. "/" .. file_path
  end
  return file_path
end

---Find file in state by path
---@param path string File path
---@return Review.File?
function M.find_file(path)
  local file, _ = state.find_file(path)
  return file
end

---Get base ref for current review
---@return string base ref
function M.get_base_ref()
  if state.state.mode == "pr" and state.state.pr then
    return state.state.pr.base
  end
  return state.state.base or "HEAD"
end

---Get head ref for current review
---@return string? head ref (nil for working tree)
function M.get_head_ref()
  if state.state.mode == "pr" and state.state.pr then
    -- For remote mode, use the PR branch
    if state.state.pr_mode == "remote" then
      return state.state.pr.branch
    end
    -- For local mode, use working tree (nil)
    return nil
  end
  return nil -- Local mode uses working tree
end

---Create a buffer for file content at a specific ref
---@param file_path string File path
---@param ref string Git ref
---@param opts? {readonly?: boolean}
---@return number? buf Buffer handle or nil on error
function M.create_ref_buffer(file_path, ref, opts)
  opts = opts or {}
  local readonly = opts.readonly ~= false

  local content = git.show_file(ref, file_path)
  if not content then
    return nil
  end

  local buf = vim.api.nvim_create_buf(false, true)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- Set content
  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Set buffer options
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = not readonly

  -- Try to set filetype based on file extension
  local ext = file_path:match("%.([^%.]+)$")
  if ext then
    local ft = vim.filetype.match({ filename = file_path })
    if ft then
      vim.bo[buf].filetype = ft
    end
  end

  -- Set buffer name
  local name = string.format("[%s] %s", ref, file_path)
  pcall(vim.api.nvim_buf_set_name, buf, name)

  return buf
end

---Open a file in diff view (local mode)
---Shows working tree version vs base ref
---@param file_path string File path to open
---@return boolean success
function M.open_local_diff(file_path)
  local diff_win = layout.get_diff_win()
  if not diff_win then
    vim.notify("Review layout not open", vim.log.levels.ERROR)
    return false
  end

  local base = M.get_base_ref()
  local file_data = M.find_file(file_path)

  -- Close any existing diff buffers
  M.close_diff_buffers()

  -- Focus diff window
  vim.api.nvim_set_current_win(diff_win)

  if file_data and file_data.status == "added" then
    -- New file - just show the current file, no diff
    -- Use edit! to force switch even if current buffer is modified
    vim.cmd("edit! " .. vim.fn.fnameescape(to_absolute_path(file_path)))
    local buf = vim.api.nvim_get_current_buf()
    state.state.layout.diff_buf = buf
    diff_buffers.new_buf = buf
    diff_buffers.new_win = vim.api.nvim_get_current_win()
    M.setup_diff_keymaps(buf)
    return true
  end

  if file_data and file_data.status == "deleted" then
    -- Deleted file - show only the old version
    local old_buf = M.create_ref_buffer(file_path, base, { readonly = true })
    if not old_buf then
      vim.notify("Could not get file content from " .. base, vim.log.levels.ERROR)
      return false
    end
    vim.api.nvim_win_set_buf(diff_win, old_buf)
    diff_buffers.old_buf = old_buf
    state.state.layout.diff_buf = old_buf
    M.setup_diff_keymaps(old_buf)
    return true
  end

  -- Normal case: show side-by-side diff
  -- Create vertical split for old version (leftward split stays in diff area)
  vim.cmd("leftabove vsplit")

  local old_win = vim.api.nvim_get_current_win()
  diff_buffers.old_win = old_win

  -- Load old version
  local old_buf = M.create_ref_buffer(file_path, base, { readonly = true })
  if old_buf then
    vim.api.nvim_win_set_buf(old_win, old_buf)
    diff_buffers.old_buf = old_buf
    vim.cmd("diffthis")
  else
    -- File doesn't exist in base - this might be a new file
    vim.cmd("enew")
    vim.bo.buftype = "nofile"
    vim.cmd("diffthis")
  end

  -- Move to right window and load current file
  vim.cmd("wincmd l")
  local new_win = vim.api.nvim_get_current_win()
  diff_buffers.new_win = new_win

  vim.cmd("edit! " .. vim.fn.fnameescape(to_absolute_path(file_path)))
  local new_buf = vim.api.nvim_get_current_buf()
  diff_buffers.new_buf = new_buf
  state.state.layout.diff_buf = new_buf

  vim.cmd("diffthis")

  -- Set window options for better diff viewing
  M.setup_diff_window_options(old_win)
  M.setup_diff_window_options(new_win)

  -- Set keymaps for diff buffers
  M.setup_diff_keymaps(old_buf)
  M.setup_diff_keymaps(new_buf)

  return true
end

---Open a file in diff view (PR mode)
---@param file_path string File path to open
---@return boolean success
function M.open_pr_diff(file_path)
  local diff_win = layout.get_diff_win()
  if not diff_win then
    vim.notify("Review layout not open", vim.log.levels.ERROR)
    return false
  end

  local pr = state.state.pr
  if not pr then
    vim.notify("No PR data available", vim.log.levels.ERROR)
    return false
  end

  local file_data = M.find_file(file_path)

  -- Close any existing diff buffers
  M.close_diff_buffers()

  -- Focus diff window
  vim.api.nvim_set_current_win(diff_win)

  local base_ref = pr.base
  local head_ref = pr.branch

  -- For local PR mode (checked out branch), use working tree
  local use_working_tree = state.state.pr_mode == "local"

  if file_data and file_data.status == "added" then
    -- New file
    if use_working_tree then
      vim.cmd("edit! " .. vim.fn.fnameescape(to_absolute_path(file_path)))
    else
      local new_buf = M.create_ref_buffer(file_path, head_ref, { readonly = true })
      if new_buf then
        vim.api.nvim_win_set_buf(diff_win, new_buf)
        diff_buffers.new_buf = new_buf
      end
    end
    local buf = vim.api.nvim_get_current_buf()
    state.state.layout.diff_buf = buf
    M.setup_diff_keymaps(buf)
    return true
  end

  if file_data and file_data.status == "deleted" then
    -- Deleted file - show only the old version
    local old_buf = M.create_ref_buffer(file_path, base_ref, { readonly = true })
    if old_buf then
      vim.api.nvim_win_set_buf(diff_win, old_buf)
      diff_buffers.old_buf = old_buf
      state.state.layout.diff_buf = old_buf
      M.setup_diff_keymaps(old_buf)
    end
    return true
  end

  -- Normal diff view (leftward split stays in diff area)
  vim.cmd("leftabove vsplit")

  local old_win = vim.api.nvim_get_current_win()
  diff_buffers.old_win = old_win

  -- Load base version
  local old_buf = M.create_ref_buffer(file_path, base_ref, { readonly = true })
  if old_buf then
    vim.api.nvim_win_set_buf(old_win, old_buf)
    diff_buffers.old_buf = old_buf
    vim.cmd("diffthis")
  else
    vim.cmd("enew")
    vim.bo.buftype = "nofile"
    vim.cmd("diffthis")
  end

  -- Move to right and load head version
  vim.cmd("wincmd l")
  local new_win = vim.api.nvim_get_current_win()
  diff_buffers.new_win = new_win

  if use_working_tree then
    -- Local mode: edit actual file
    vim.cmd("edit! " .. vim.fn.fnameescape(to_absolute_path(file_path)))
    diff_buffers.new_buf = vim.api.nvim_get_current_buf()
  else
    -- Remote mode: show PR branch version (read-only)
    local new_buf = M.create_ref_buffer(file_path, head_ref, { readonly = true })
    if new_buf then
      vim.api.nvim_win_set_buf(new_win, new_buf)
      diff_buffers.new_buf = new_buf
    end
  end

  state.state.layout.diff_buf = vim.api.nvim_get_current_buf()
  vim.cmd("diffthis")

  M.setup_diff_window_options(old_win)
  M.setup_diff_window_options(new_win)

  -- Set keymaps for diff buffers
  M.setup_diff_keymaps(diff_buffers.old_buf)
  M.setup_diff_keymaps(diff_buffers.new_buf)

  return true
end

---Open a file in diff view (auto-detects mode)
---@param file_path string File path to open
---@return boolean success
function M.open_file(file_path)
  if not state.is_active() then
    vim.notify("No active review session", vim.log.levels.ERROR)
    return false
  end

  local file_data = M.find_file(file_path)
  if not file_data then
    vim.notify("File not found in review: " .. file_path, vim.log.levels.WARN)
    -- Try to open anyway for files that might not be in diff
  end

  state.set_current_file(file_path)

  local success
  if state.state.mode == "pr" then
    success = M.open_pr_diff(file_path)
  else
    success = M.open_local_diff(file_path)
  end

  if success then
    -- Jump to first hunk and trigger UI refresh
    vim.schedule(function()
      M.jump_to_first_hunk()
      M.refresh_decorations()
    end)
  end

  return success
end

---Setup window options for diff viewing
---@param win number Window handle
function M.setup_diff_window_options(win)
  if not utils.is_valid_win(win) then
    return
  end

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].foldmethod = "diff"
  vim.wo[win].foldlevel = 99 -- Start with folds open
  vim.wo[win].scrollbind = true
  vim.wo[win].cursorbind = true
end

---Setup keymaps for diff buffer
---@param buf number Buffer handle
function M.setup_diff_keymaps(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local opts = { buffer = buf, nowait = true, silent = true }

  -- Close entire review with q
  vim.keymap.set("n", "q", function()
    layout.close()
  end, opts)

  -- Cross-file hunk navigation with Tab/S-Tab
  vim.keymap.set("n", "<Tab>", function()
    local nav = utils.safe_require("review.core.navigation")
    if nav then
      nav.next_hunk_across_files()
    end
  end, opts)

  vim.keymap.set("n", "<S-Tab>", function()
    local nav = utils.safe_require("review.core.navigation")
    if nav then
      nav.prev_hunk_across_files()
    end
  end, opts)
end

---Close diff buffers and reset state
function M.close_diff_buffers()
  -- Turn off diff mode in windows
  if diff_buffers.old_win and vim.api.nvim_win_is_valid(diff_buffers.old_win) then
    vim.api.nvim_set_current_win(diff_buffers.old_win)
    pcall(vim.cmd, "diffoff")
    vim.api.nvim_win_close(diff_buffers.old_win, true)
  end

  if diff_buffers.new_win and vim.api.nvim_win_is_valid(diff_buffers.new_win) then
    vim.api.nvim_set_current_win(diff_buffers.new_win)
    pcall(vim.cmd, "diffoff")
  end

  -- Delete old buffer
  if diff_buffers.old_buf and vim.api.nvim_buf_is_valid(diff_buffers.old_buf) then
    vim.api.nvim_buf_delete(diff_buffers.old_buf, { force = true })
  end

  -- Reset tracking
  diff_buffers = {}
end

---Refresh diff after file edit
function M.refresh()
  local current_file = state.state.current_file
  if current_file then
    -- Refresh diff update
    pcall(vim.cmd, "diffupdate")
  end
end

---Refresh decorations (signs, virtual text)
function M.refresh_decorations()
  -- Safe require to avoid circular dependencies
  local signs = utils.safe_require("review.ui.signs")
  local virtual_text = utils.safe_require("review.ui.virtual_text")

  if signs then
    pcall(signs.refresh)
  end
  if virtual_text then
    pcall(virtual_text.refresh)
  end
end

---Get the current diff buffer (new/editable side)
---@return number? buffer handle
function M.get_current_buf()
  return diff_buffers.new_buf or state.state.layout.diff_buf
end

---Get the old diff buffer (base side)
---@return number? buffer handle
function M.get_old_buf()
  return diff_buffers.old_buf
end

---Check if currently in diff mode
---@return boolean
function M.is_diff_mode()
  return diff_buffers.old_buf ~= nil or diff_buffers.new_buf ~= nil
end

---Get line number in current file at cursor
---@return number? line number
function M.get_cursor_line()
  local win = layout.get_diff_win()
  if not win then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return cursor[1]
end

---Jump to a specific line in the diff view
---@param line number Line number to jump to
function M.goto_line(line)
  local win = diff_buffers.new_win or layout.get_diff_win()
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_set_current_win(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)

  if line > 0 and line <= line_count then
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    -- Center the view
    vim.cmd("normal! zz")
  end
end

---Navigate to next hunk
function M.next_hunk()
  pcall(vim.cmd, "normal! ]c")
end

---Navigate to previous hunk
function M.prev_hunk()
  pcall(vim.cmd, "normal! [c")
end

---Jump to first hunk in current diff
function M.jump_to_first_hunk()
  local win = diff_buffers.new_win or layout.get_diff_win()
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.api.nvim_set_current_win(win)

  -- Go to top of file first
  vim.cmd("normal! gg")

  -- Then jump to first change
  -- Use pcall as there might be no diff hunks
  pcall(vim.cmd, "normal! ]c")
end

---Get hunk at current cursor position
---@return Review.Hunk?
function M.get_hunk_at_cursor()
  local file_path = state.state.current_file
  if not file_path then
    return nil
  end

  local file_data = M.find_file(file_path)
  if not file_data or not file_data.hunks then
    return nil
  end

  local line = M.get_cursor_line()
  if not line then
    return nil
  end

  local diff_parser = utils.safe_require("review.core.diff_parser")
  if not diff_parser then
    return nil
  end

  local hunk, _ = diff_parser.find_hunk_for_line(file_data.hunks, line)
  return hunk
end

---Setup autocmds for diff buffer management
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup("ReviewDiff", { clear = true })

  -- Refresh decorations on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function()
      if state.is_active() and state.state.current_file then
        vim.schedule(function()
          M.refresh_decorations()
        end)
      end
    end,
  })

  -- Update diff after save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function()
      if state.is_active() then
        M.refresh()
        M.refresh_decorations()
      end
    end,
  })
end

---Cleanup autocmds
function M.cleanup_autocmds()
  pcall(vim.api.nvim_del_augroup_by_name, "ReviewDiff")
end

---Cleanup on review close
function M.cleanup()
  M.close_diff_buffers()
  M.cleanup_autocmds()
end

return M
